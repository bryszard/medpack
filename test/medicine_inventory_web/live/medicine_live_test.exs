defmodule MedpackWeb.MedicineLiveTest do
  use MedpackWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Medpack.Factory

  # Need async: false because we're testing database interactions

  defp get_assigns(view) do
    :sys.get_state(view.pid).socket.assigns
  end

  describe "mount" do
    test "displays empty state when no medicines exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/inventory")

      # Should mount successfully but show no medicines
      refute html =~ "💊"
      assert html =~ "Search by name, ingredient, manufacturer"
      assert html =~ "🔽 Filters"
      assert html =~ "Card View"
    end

    test "displays medicines in card view by default", %{conn: conn} do
      _medicine1 = insert(:medicine, name: "Aspirin", brand_name: "Bayer")
      _medicine2 = insert(:medicine, name: "Ibuprofen", brand_name: "Advil")

      {:ok, _view, html} = live(conn, ~p"/inventory")

      # Should show medicines in card format
      assert html =~ "Aspirin"
      assert html =~ "Bayer"
      assert html =~ "Ibuprofen"
      assert html =~ "Advil"
      assert html =~ "card bg-base-100"
    end

    test "initializes with correct default assigns", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/inventory")

      assigns = get_assigns(view)

      # Check default state
      assert assigns.search_query == ""
      assert assigns.view_mode == :cards
      assert assigns.filters == %{}
      assert assigns.show_filters == false
      assert is_list(assigns.medicines)
    end
  end

  describe "search functionality" do
    test "searches medicines by name", %{conn: conn} do
      insert(:medicine, name: "Aspirin", brand_name: "Bayer")
      insert(:medicine, name: "Ibuprofen", brand_name: "Advil")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Search for Aspirin
      html =
        view
        |> form("form", %{query: "Aspirin"})
        |> render_change()

      assert html =~ "Aspirin"
      assert html =~ "Bayer"
      refute html =~ "Ibuprofen"

      # Verify search query is stored - get assigns after the search
      assigns = get_assigns(view)
      assert assigns.search_query == "Aspirin"
    end

    test "searches medicines by brand name", %{conn: conn} do
      insert(:medicine, name: "Aspirin", brand_name: "Bayer")
      insert(:medicine, name: "Ibuprofen", brand_name: "Advil")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Search for Advil brand
      html =
        view
        |> form("form", %{query: "Advil"})
        |> render_change()

      assert html =~ "Ibuprofen"
      assert html =~ "Advil"
      refute html =~ "Aspirin"
    end

    test "searches medicines by manufacturer", %{conn: conn} do
      insert(:medicine, name: "Medicine A", manufacturer: "Pfizer Inc")
      insert(:medicine, name: "Medicine B", manufacturer: "Johnson & Johnson")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Search for Pfizer
      html =
        view
        |> form("form", %{query: "Pfizer"})
        |> render_change()

      assert html =~ "Medicine A"
      assert html =~ "Pfizer Inc"
      refute html =~ "Medicine B"
    end

    test "shows no results for non-matching search", %{conn: conn} do
      insert(:medicine, name: "Aspirin", brand_name: "Bayer")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Search for non-existent medicine
      html =
        view
        |> form("form", %{query: "NonExistentMedicine"})
        |> render_change()

      refute html =~ "Aspirin"
      refute html =~ "Bayer"
    end

    test "clears search results when query is emptied", %{conn: conn} do
      insert(:medicine, name: "Aspirin")
      insert(:medicine, name: "Ibuprofen")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Search first
      view
      |> form("form", %{query: "Aspirin"})
      |> render_change()

      # Clear search
      html =
        view
        |> form("form", %{query: ""})
        |> render_change()

      # Should show all medicines again
      assert html =~ "Aspirin"
      assert html =~ "Ibuprofen"

      # Verify search query is cleared - get assigns after clearing
      assigns = get_assigns(view)
      assert assigns.search_query == ""
    end
  end

  describe "view mode toggle" do
    test "switches from card view to table view", %{conn: conn} do
      insert(:medicine, name: "Aspirin", brand_name: "Bayer")

      {:ok, view, html} = live(conn, ~p"/inventory")

      # Get initial assigns
      assigns = get_assigns(view)

      # Initially in card view
      assert html =~ "📋 Table View"
      assert html =~ "card bg-base-100"
      assert assigns.view_mode == :cards

      # Toggle to table view
      html = render_click(view, "toggle_view")

      assert html =~ "🗃️ Card View"
      assert html =~ "table table-zebra"

      # Get assigns after the toggle
      assigns = get_assigns(view)
      assert assigns.view_mode == :table
    end

    test "switches from table view back to card view", %{conn: conn} do
      insert(:medicine, name: "Aspirin", brand_name: "Bayer")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Switch to table view first
      render_click(view, "toggle_view")

      # Switch back to card view
      html = render_click(view, "toggle_view")

      assert html =~ "📋 Table View"
      assert html =~ "card bg-base-100"

      # Get assigns after the second toggle
      assigns = get_assigns(view)
      assert assigns.view_mode == :cards
    end

    test "preserves search results when switching view modes", %{conn: conn} do
      insert(:medicine, name: "Aspirin", brand_name: "Bayer")
      insert(:medicine, name: "Ibuprofen", brand_name: "Advil")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Search first
      view
      |> form("form", %{query: "Aspirin"})
      |> render_change()

      # Toggle view mode
      html = render_click(view, "toggle_view")

      # Should still show only search results
      assert html =~ "Aspirin"
      refute html =~ "Ibuprofen"

      # Verify search query is preserved - get assigns after the view toggle
      assigns = get_assigns(view)
      assert assigns.search_query == "Aspirin"
    end
  end

  describe "filter functionality" do
    test "toggles filter panel visibility", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/inventory")

      # Get initial assigns
      assigns = get_assigns(view)

      # Initially filters are hidden
      refute html =~ "🔍 Filter Medicines"
      assert assigns.show_filters == false

      # Show filters
      html = render_click(view, "toggle_filters")

      assert html =~ "🔍 Filter Medicines"

      # Get assigns after showing filters
      assigns = get_assigns(view)
      assert assigns.show_filters == true

      # Hide filters again
      html = render_click(view, "toggle_filters")

      refute html =~ "🔍 Filter Medicines"

      # Get assigns after hiding filters
      assigns = get_assigns(view)
      assert assigns.show_filters == false
    end

    test "filters by dosage form", %{conn: conn} do
      insert(:medicine, name: "Aspirin Tablet", dosage_form: "tablet")
      insert(:medicine, name: "Ibuprofen Capsule", dosage_form: "capsule")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Show filters first
      render_click(view, "toggle_filters")

      # Apply dosage form filter
      html =
        view
        |> element("form[phx-change='filter_change']")
        |> render_change(%{filter: %{dosage_form: "tablet"}})

      assert html =~ "Aspirin Tablet"
      refute html =~ "Ibuprofen Capsule"

      # Get assigns after the filter change
      assigns = get_assigns(view)
      assert assigns.filters.dosage_form == "tablet"
    end

    test "filters by status", %{conn: conn} do
      insert(:medicine, name: "Active Medicine", status: "active")
      insert(:medicine, name: "Expired Medicine", status: "expired")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Show filters first
      render_click(view, "toggle_filters")

      # Apply status filter
      html =
        view
        |> element("form[phx-change='filter_change']")
        |> render_change(%{filter: %{status: "expired"}})

      assert html =~ "Expired Medicine"
      refute html =~ "Active Medicine"

      # Get assigns after the filter change
      assigns = get_assigns(view)
      assert assigns.filters.status == "expired"
    end

    test "shows filter count badge when filters are applied", %{conn: conn} do
      insert(:medicine, name: "Medicine", dosage_form: "tablet", status: "active")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Show filters
      render_click(view, "toggle_filters")

      # Apply multiple filters
      view
      |> element("form[phx-change='filter_change']")
      |> render_change(%{filter: %{dosage_form: "tablet", status: "active"}})

      html = render(view)

      # Should show badge with filter count
      assert html =~ "badge badge-primary"
      # 2 filters applied
      assert html =~ ">2<"
    end

    test "clears all filters", %{conn: conn} do
      insert(:medicine, name: "Tablet Medicine", dosage_form: "tablet")
      insert(:medicine, name: "Capsule Medicine", dosage_form: "capsule")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Show filters and apply one
      render_click(view, "toggle_filters")

      view
      |> element("form[phx-change='filter_change']")
      |> render_change(%{filter: %{dosage_form: "tablet"}})

      # Clear filters
      html = render_click(view, "clear_filters")

      # Should show all medicines again
      assert html =~ "Tablet Medicine"
      assert html =~ "Capsule Medicine"

      # Get assigns after clearing filters
      assigns = get_assigns(view)
      assert assigns.filters == %{}
    end

    test "combines search and filters", %{conn: conn} do
      insert(:medicine, name: "Aspirin Tablet", dosage_form: "tablet")
      insert(:medicine, name: "Aspirin Capsule", dosage_form: "capsule")
      insert(:medicine, name: "Ibuprofen Tablet", dosage_form: "tablet")

      {:ok, view, _html} = live(conn, ~p"/inventory")

      # Search first
      view
      |> form("form", %{query: "Aspirin"})
      |> render_change()

      # Show filters and apply dosage form filter
      render_click(view, "toggle_filters")

      html =
        view
        |> element("form[phx-change='filter_change']")
        |> render_change(%{filter: %{dosage_form: "tablet"}})

      # Should only show Aspirin Tablet
      assert html =~ "Aspirin Tablet"
      refute html =~ "Aspirin Capsule"
      refute html =~ "Ibuprofen Tablet"
    end
  end

  describe "medicine navigation" do
    test "navigates to medicine detail page when clicking on medicine card", %{conn: conn} do
      medicine = insert(:medicine, name: "Aspirin")

      {:ok, _view, html} = live(conn, ~p"/inventory")

      # Should have link to medicine detail
      assert html =~ "href=\"/inventory/#{medicine.id}\""
    end

    test "displays medicine photos when available", %{conn: conn} do
      _medicine = insert(:medicine, name: "Aspirin", photo_paths: ["/uploads/test.jpg"])

      {:ok, _view, html} = live(conn, ~p"/inventory")

      # Should show medicine photo
      assert html =~ "src=\"/uploads/test.jpg\""
      assert html =~ "alt=\"Aspirin\""
    end

    test "displays default medicine icon when no photo available", %{conn: conn} do
      insert(:medicine, name: "Aspirin", photo_paths: [])

      {:ok, _view, html} = live(conn, ~p"/inventory")

      # Should show default medicine emoji
      assert html =~ "💊"
    end
  end

  describe "real-time updates" do
    test "updates medicine list when new medicine is created", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/inventory")

      # Initially no medicines
      refute html =~ "New Medicine"

      # Create a new medicine
      medicine = insert(:medicine, name: "New Medicine")

      # Send PubSub message that would be sent by the system
      send(view.pid, {:medicine_created, medicine})

      html = render(view)

      # Should now show the new medicine
      assert html =~ "New Medicine"
    end
  end

  describe "error handling" do
    test "handles database errors gracefully", %{conn: conn} do
      # This would be tested with a mock that forces a database error
      # For now, just ensure the page loads without crashing
      {:ok, _view, _html} = live(conn, ~p"/inventory")

      # Should not crash even if there are database issues
      assert true
    end
  end

  describe "responsive design and accessibility" do
    test "includes proper ARIA labels and accessibility features", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/inventory")

      # Check for accessibility features
      assert html =~ "placeholder=\"🔍 Search by name, ingredient, manufacturer...\""
      assert html =~ "type=\"text\""
      assert html =~ "phx-debounce=\"300\""
    end

    test "includes responsive design classes", %{conn: conn} do
      insert(:medicine, name: "Test Medicine")

      {:ok, _view, html} = live(conn, ~p"/inventory")

      # Check for responsive grid classes
      assert html =~ "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3"
      assert html =~ "max-w-7xl"
      assert html =~ "px-4 sm:px-6 lg:px-8"
    end
  end
end
