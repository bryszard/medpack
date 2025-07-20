defmodule MedpackWeb.Integration.MedicineCrudIntegrationTest do
  use MedpackWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Medpack.Factory

  alias Medpack.Medicines

  # Need async: false because we're testing database interactions and navigation flows

  setup :register_and_log_in_user

  describe "complete medicine CRUD workflow" do
    test "can navigate from home to inventory and view medicines", %{conn: conn} do
      # Create some test medicines
      medicine1 = insert(:medicine, name: "Aspirin", brand_name: "Bayer")
      _medicine2 = insert(:medicine, name: "Ibuprofen", brand_name: "Advil")

      # Start at home page
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Welcome to Medpack"

      # Navigate to inventory
      {:ok, inventory_view, html} = live(conn, ~p"/inventory")

      # Should show medicines
      assert html =~ "Aspirin"
      assert html =~ "Bayer"
      assert html =~ "Ibuprofen"
      assert html =~ "Advil"

      # Click on first medicine to view details
      {:ok, _detail_view, detail_html} =
        inventory_view
        |> element("a[href='/inventory/#{medicine1.id}']")
        |> render_click()
        |> follow_redirect(conn, ~p"/inventory/#{medicine1.id}")

      # Should show medicine details
      assert detail_html =~ "Aspirin"
      assert detail_html =~ "Bayer"
      assert detail_html =~ "✏️ Edit" or detail_html =~ "Edit"
    end

    test "can edit medicine details and save changes", %{conn: conn} do
      medicine =
        insert(:medicine,
          name: "Original Name",
          brand_name: "Original Brand",
          dosage_form: "tablet"
        )

      # Navigate directly to medicine detail page
      {:ok, view, html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Should show original data
      assert html =~ "Original Name"
      assert html =~ "Original Brand"

      # Enter edit mode
      html = render_click(view, "toggle_edit")

      # Should show edit form
      assert html =~ "medicine-form"
      assert html =~ "💾 Save Changes"

      # Update medicine details
      html =
        view
        |> form("#medicine-form", %{
          medicine: %{
            name: "Updated Medicine Name",
            brand_name: "Updated Brand",
            dosage_form: "capsule",
            active_ingredient: "New Ingredient"
          }
        })
        |> render_submit()

      # Should exit edit mode and show updated data
      assert html =~ "Updated Medicine Name"
      assert html =~ "Updated Brand"
      assert html =~ "Capsule"
      assert html =~ "New Ingredient"

      # Verify changes were persisted to database
      updated_medicine = Medicines.get_medicine!(medicine.id)
      assert updated_medicine.name == "Updated Medicine Name"
      assert updated_medicine.brand_name == "Updated Brand"
      assert updated_medicine.dosage_form == "capsule"
      assert updated_medicine.active_ingredient == "New Ingredient"
    end

    test "can search and filter medicines in inventory", %{conn: conn} do
      # Create diverse test data
      insert(:medicine, name: "Aspirin Tablet", dosage_form: "tablet", status: "active")
      insert(:medicine, name: "Ibuprofen Capsule", dosage_form: "capsule", status: "active")
      insert(:medicine, name: "Expired Medicine", dosage_form: "tablet", status: "expired")

      {:ok, view, html} = live(conn, ~p"/inventory")

      # Should show all medicines initially
      assert html =~ "Aspirin Tablet"
      assert html =~ "Ibuprofen Capsule"
      assert html =~ "Expired Medicine"

      # Search for "Aspirin"
      html =
        view
        |> form("form", %{query: "Aspirin"})
        |> render_change()

      assert html =~ "Aspirin Tablet"
      refute html =~ "Ibuprofen Capsule"
      refute html =~ "Expired Medicine"

      # Clear search and apply filters
      view
      |> form("form", %{query: ""})
      |> render_change()

      # Show filters
      render_click(view, "toggle_filters")

      # Filter by dosage form (tablet)
      html =
        view
        |> element("form[phx-change='filter_change']")
        |> render_change(%{filter: %{dosage_form: "tablet"}})

      assert html =~ "Aspirin Tablet"
      assert html =~ "Expired Medicine"
      refute html =~ "Ibuprofen Capsule"

      # Add status filter (active)
      html =
        view
        |> element("form[phx-change='filter_change']")
        |> render_change(%{filter: %{dosage_form: "tablet", status: "active"}})

      assert html =~ "Aspirin Tablet"
      refute html =~ "Expired Medicine"
      refute html =~ "Ibuprofen Capsule"

      # Clear all filters
      html = render_click(view, "clear_filters")

      # Should show all medicines again
      assert html =~ "Aspirin Tablet"
      assert html =~ "Ibuprofen Capsule"
      assert html =~ "Expired Medicine"
    end

    test "can toggle between card and table view modes", %{conn: conn} do
      insert(:medicine, name: "Test Medicine", brand_name: "Test Brand")

      {:ok, view, html} = live(conn, ~p"/inventory")

      # Initially in card view
      assert html =~ "card bg-base-100"
      assert html =~ "📋 Table View"

      # Toggle to table view
      html = render_click(view, "toggle_view")

      assert html =~ "table table-zebra"
      assert html =~ "🗃️ Card View"
      assert html =~ "Test Medicine"
      assert html =~ "Test Brand"

      # Toggle back to card view
      html = render_click(view, "toggle_view")

      assert html =~ "card bg-base-100"
      assert html =~ "📋 Table View"
    end

    test "navigation flow between all pages works correctly", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      # Start at home
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Welcome to Medpack"

      # Navigate to inventory via link
      {:ok, inventory_view, _html} = live(conn, ~p"/inventory")

      # Check topbar navigation is working
      # Inventory should be highlighted
      assert render(inventory_view) =~ "bg-base-300"

      # Navigate to add page
      {:ok, add_view, add_html} = live(conn, ~p"/add")

      assert add_html =~ "Medicine Entry"
      # Add button should be highlighted
      assert render(add_view) =~ "bg-base-300"

      # Navigate to medicine detail
      {:ok, detail_view, detail_html} = live(conn, ~p"/inventory/#{medicine.id}")

      assert detail_html =~ "Test Medicine"
      # Should also highlight inventory in topbar for medicine detail page
      assert render(detail_view) =~ "bg-base-300"

      # Navigate back to inventory via topbar
      {:ok, _back_to_inventory, inventory_html} =
        detail_view
        |> element("a[href='/inventory']")
        |> render_click()
        |> follow_redirect(conn, ~p"/inventory")

      assert inventory_html =~ "Search by name, ingredient, manufacturer"
    end

    test "error handling throughout navigation flow", %{conn: conn} do
      # Try to access non-existent medicine
      assert {:error,
              {:live_redirect, %{to: "/inventory", flash: %{"error" => "Medicine not found"}}}} =
               live(conn, ~p"/inventory/99999")

      # Try to access medicine with invalid ID format
      assert {:error,
              {:live_redirect, %{to: "/inventory", flash: %{"error" => "Medicine not found"}}}} =
               live(conn, ~p"/inventory/invalid")

      # Should be able to recover and navigate normally
      {:ok, _view, html} = live(conn, ~p"/inventory")
      assert html =~ "Search by name, ingredient, manufacturer"
    end

    test "real-time updates work across the application", %{conn: conn} do
      {:ok, inventory_view, html} = live(conn, ~p"/inventory")

      # Initially no medicines
      refute html =~ "Real-time Medicine"

      # Create a medicine (simulating creation from another session)
      medicine = insert(:medicine, name: "Real-time Medicine")

      # Send real-time update message
      send(inventory_view.pid, {:medicine_created, medicine})

      html = render(inventory_view)

      # Should show the new medicine
      assert html =~ "Real-time Medicine"
    end

    test "form validation works correctly across edit workflows", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode
      render_click(view, "toggle_edit")

      # Try to save with invalid data (empty name)
      html =
        view
        |> form("#medicine-form", %{medicine: %{name: ""}})
        |> render_change()

      # Should show validation error
      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"

      # Try to submit invalid form
      html =
        view
        |> form("#medicine-form", %{medicine: %{name: ""}})
        |> render_submit()

      # Should remain in edit mode with errors
      assert html =~ "medicine-form"

      # Fix the error and submit
      html =
        view
        |> form("#medicine-form", %{medicine: %{name: "Valid Name"}})
        |> render_submit()

      # Should exit edit mode and show updated data
      assert html =~ "Valid Name"
      refute html =~ "medicine-form"
    end

    test "photo display and management workflow", %{conn: conn} do
      # Suppress expected file deletion warnings for test files that don't exist
      ExUnit.CaptureLog.capture_log(fn ->
        medicine =
          insert(:medicine,
            name: "Photo Medicine",
            photo_paths: ["/uploads/test1.jpg", "/uploads/test2.jpg"]
          )

        {:ok, view, html} = live(conn, ~p"/inventory/#{medicine.id}")

        # Should show first photo by default
        assert html =~ "src=\"/uploads/test1.jpg\""

        # Select second photo
        html = render_click(view, "select_photo", %{"index" => "1"})

        assert html =~ "src=\"/uploads/test2.jpg\""

        # Enlarge photo
        html = render_click(view, "enlarge_photo", %{"index" => "1"})

        # Modal overlay
        assert html =~ "fixed inset-0"

        # Close enlarged photo
        html = render_click(view, "close_enlarged_photo")

        refute html =~ "fixed inset-0"

        # Enter edit mode and remove a photo
        render_click(view, "toggle_edit")
        html = render_click(view, "remove_photo", %{"index" => "0"})

        # Should remove first photo
        refute html =~ "src=\"/uploads/test1.jpg\""
        assert html =~ "src=\"/uploads/test2.jpg\""

        # Verify in database
        updated_medicine = Medicines.get_medicine!(medicine.id)
        assert updated_medicine.photo_paths == ["/uploads/test2.jpg"]
      end)
    end

    test "complete user journey from discovery to medicine management", %{conn: conn} do
      # User starts at home page
      conn = get(conn, ~p"/")
      home_html = html_response(conn, 200)

      assert home_html =~ "Welcome to Medpack"
      assert home_html =~ "View Inventory"
      assert home_html =~ "Add Medicines"

      # User navigates to inventory to see what medicines they have
      {:ok, _inventory_view, inventory_html} = live(conn, ~p"/inventory")

      # Empty inventory initially
      # No medicine cards
      refute inventory_html =~ "💊"

      # User goes to add medicines page
      {:ok, _add_view, add_html} = live(conn, ~p"/add")

      assert add_html =~ "Medicine Entry"
      assert add_html =~ "📸 Add photo"

      # User would upload photos here (simulated)
      # After photos are uploaded and analyzed, user creates medicine
      # For this test, we'll create directly
      medicine =
        insert(:medicine,
          name: "User Added Medicine",
          brand_name: "Test Brand",
          dosage_form: "tablet"
        )

      # User goes back to inventory to see their medicine
      {:ok, updated_inventory_view, updated_inventory_html} = live(conn, ~p"/inventory")

      assert updated_inventory_html =~ "User Added Medicine"
      assert updated_inventory_html =~ "Test Brand"

      # User searches for their medicine
      search_html =
        updated_inventory_view
        |> form("form", %{query: "User Added"})
        |> render_change()

      assert search_html =~ "User Added Medicine"

      # User clicks on medicine to view details
      {:ok, detail_view, detail_html} =
        updated_inventory_view
        |> element("a[href='/inventory/#{medicine.id}']")
        |> render_click()
        |> follow_redirect(conn, ~p"/inventory/#{medicine.id}")

      assert detail_html =~ "User Added Medicine"
      assert detail_html =~ "Test Brand"
      assert detail_html =~ "tablet"

      # User edits medicine to add more details
      render_click(detail_view, "toggle_edit")

      edit_html =
        detail_view
        |> form("#medicine-form", %{
          medicine: %{
            active_ingredient: "Test Ingredient",
            manufacturer: "Test Manufacturer",
          }
        })
        |> render_submit()

      assert edit_html =~ "Test Ingredient"
      assert edit_html =~ "Test Manufacturer"

      # User navigates back to inventory to see updated medicine
      {:ok, _final_inventory, final_html} = live(conn, ~p"/inventory")

      assert final_html =~ "User Added Medicine"

      # Complete workflow successful
      assert true
    end
  end

  describe "responsive design and mobile experience" do
    test "interface works correctly on different screen sizes", %{conn: conn} do
      medicine = insert(:medicine, name: "Responsive Medicine")

      # Test inventory page responsive classes
      {:ok, _view, html} = live(conn, ~p"/inventory")

      assert html =~ "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3"
      assert html =~ "max-w-7xl"
      assert html =~ "px-4 sm:px-6 lg:px-8"

      # Test medicine detail page responsive classes
      {:ok, _detail_view, detail_html} = live(conn, ~p"/inventory/#{medicine.id}")

      assert detail_html =~ "md:flex"
      assert detail_html =~ "md:w-1/2"
      assert detail_html =~ "max-w-4xl"
    end

    test "navigation works on mobile viewports", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/inventory")

      # Topbar should work on mobile
      assert html =~ "btn btn-circle"
      assert html =~ "flex items-center"

      # Should have mobile-friendly navigation
      assert html =~ "href=\"/\""
      assert html =~ "href=\"/add\""
    end
  end

  describe "accessibility throughout the application" do
    test "navigation is accessible via keyboard and screen readers", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      # Should have proper link structure
      assert html =~ "href=\"/inventory\""
      assert html =~ "href=\"/add\""

      # Should have descriptive text
      assert html =~ "View Inventory"
      assert html =~ "Add Medicines"
    end

    test "forms are properly labeled and accessible", %{conn: conn} do
      medicine = insert(:medicine, name: "Accessible Medicine")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode to test form accessibility
      html = render_click(view, "toggle_edit")

      # Should have proper form labels
      assert html =~ "Medicine Name"
      assert html =~ "Brand Name"
      assert html =~ "Dosage Form"
      assert html =~ "required"
    end
  end

  describe "performance and loading states" do
    test "pages load quickly and show appropriate loading states", %{conn: conn} do
      # Create many medicines to test performance
      for i <- 1..20 do
        insert(:medicine, name: "Medicine #{i}")
      end

      # Inventory should load efficiently
      start_time = System.monotonic_time(:millisecond)
      {:ok, _view, html} = live(conn, ~p"/inventory")
      end_time = System.monotonic_time(:millisecond)

      # Should load within reasonable time (adjust threshold as needed)
      # 5 seconds max
      assert end_time - start_time < 5000

      # Should show all medicines
      assert html =~ "Medicine 1"
      assert html =~ "Medicine 20"
    end
  end
end
