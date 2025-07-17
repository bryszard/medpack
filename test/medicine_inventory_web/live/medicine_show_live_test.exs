defmodule MedpackWeb.MedicineShowLiveTest do
  use MedpackWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Medpack.Factory
  import ExUnit.CaptureLog

  alias Medpack.Medicines

  # Need async: false because we're testing database and file operations

  # Helper function to get assigns from LiveView in Phoenix LiveView 1.0.17+
  defp get_assigns(view) do
    :sys.get_state(view.pid).socket.assigns
  end

  describe "mount with valid medicine ID" do
    test "displays medicine details in view mode", %{conn: conn} do
      medicine =
        insert(:medicine,
          name: "Aspirin",
          brand_name: "Bayer",
          dosage_form: "tablet",
          active_ingredient: "acetylsalicylic acid",
          manufacturer: "Bayer AG"
        )

      {:ok, view, html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Get assigns using the correct method for Phoenix LiveView 1.0.17
      assigns = get_assigns(view)

      # Check medicine details are displayed
      assert html =~ "Aspirin"
      assert html =~ "Bayer"
      assert html =~ "tablet"
      assert html =~ "acetylsalicylic acid"
      assert html =~ "Bayer AG"

      # Should be in view mode initially
      assert assigns.edit_mode == false
      assert assigns.medicine.id == medicine.id
    end

    test "sets correct page title", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      assigns = get_assigns(view)
      assert assigns.page_title == "Test Medicine"
    end

    test "initializes photo selection state", %{conn: conn} do
      medicine = insert(:medicine, photo_paths: ["/path1.jpg", "/path2.jpg"])

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      assigns = get_assigns(view)
      assert assigns.selected_photo_index == 0
      assert assigns.show_enlarged_photo == false
      assert assigns.enlarged_photo_index == 0
    end

    test "initializes form for editing", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      assigns = get_assigns(view)
      assert assigns.form != nil

      # Check that the form is properly initialized with the medicine data
      assert assigns.form.data.id == medicine.id
      assert assigns.form.data.name == medicine.name
    end
  end

  describe "mount with invalid medicine ID" do
    test "redirects to inventory with error message for non-existent medicine", %{conn: conn} do
      assert {:error,
              {:live_redirect, %{to: "/inventory", flash: %{"error" => "Medicine not found"}}}} =
               live(conn, ~p"/inventory/99999")
    end

    test "redirects to inventory with error message for invalid ID format", %{conn: conn} do
      assert {:error,
              {:live_redirect, %{to: "/inventory", flash: %{"error" => "Medicine not found"}}}} =
               live(conn, ~p"/inventory/invalid")
    end
  end

  describe "photo display and selection" do
    test "displays medicine photos when available", %{conn: conn} do
      medicine =
        insert(:medicine,
          name: "Test Medicine",
          photo_paths: ["/uploads/photo1.jpg", "/uploads/photo2.jpg"]
        )

      {:ok, _view, html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Should show first photo by default
      assert html =~ "src=\"/uploads/photo1.jpg\""
      assert html =~ "alt=\"Test Medicine\""
    end

    test "displays default photo placeholder when no photos", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine", photo_paths: [])

      {:ok, _view, html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Should show placeholder
      assert html =~ "💊"
      # Note: The template only shows the pill emoji, no "No photos available" text
    end

    test "selects different photo when clicking thumbnail", %{conn: conn} do
      medicine =
        insert(:medicine,
          photo_paths: ["/uploads/photo1.jpg", "/uploads/photo2.jpg"]
        )

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Select second photo
      html = render_click(view, "select_photo", %{"index" => "1"})

      assert html =~ "src=\"/uploads/photo2.jpg\""
      assigns = get_assigns(view)
      assert assigns.selected_photo_index == 1
    end

    test "enlarges photo when clicking enlarge button", %{conn: conn} do
      medicine =
        insert(:medicine,
          photo_paths: ["/uploads/photo1.jpg", "/uploads/photo2.jpg"]
        )

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enlarge first photo
      html = render_click(view, "enlarge_photo", %{"index" => "0"})

      assigns = get_assigns(view)
      assert assigns.show_enlarged_photo == true
      assert assigns.enlarged_photo_index == 0
      # Should show enlarged photo modal
      # Modal overlay
      assert html =~ "fixed inset-0"
    end

    test "closes enlarged photo modal", %{conn: conn} do
      medicine = insert(:medicine, photo_paths: ["/uploads/photo1.jpg"])

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enlarge photo first
      render_click(view, "enlarge_photo", %{"index" => "0"})

      # Close enlarged photo
      html = render_click(view, "close_enlarged_photo")

      assigns = get_assigns(view)
      assert assigns.show_enlarged_photo == false
      refute html =~ "fixed inset-0"
    end
  end

  describe "edit mode functionality" do
    test "toggles to edit mode", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, view, html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Initially in view mode
      refute html =~ "medicine-form"

      # Toggle to edit mode
      html = render_click(view, "toggle_edit")

      assigns = get_assigns(view)
      assert assigns.edit_mode == true
      assert html =~ "medicine-form"
      assert html =~ "💾 Save Changes"
      assert html =~ "❌ Cancel"
    end

    test "cancels edit mode without saving changes", %{conn: conn} do
      medicine = insert(:medicine, name: "Original Name")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode
      render_click(view, "toggle_edit")

      # Make some changes (this would be done via form change)
      view
      |> form("#medicine-form", %{medicine: %{name: "Changed Name"}})
      |> render_change()

      # Cancel editing
      html = render_click(view, "cancel_edit")

      assigns = get_assigns(view)
      assert assigns.edit_mode == false
      refute html =~ "medicine-form"
      # Should show original data
      assert html =~ "Original Name"
    end

    test "validates form changes in edit mode", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode
      render_click(view, "toggle_edit")

      # Make invalid changes
      html =
        view
        # Empty name
        |> form("#medicine-form", %{medicine: %{name: ""}})
        |> render_change()

      # Should show validation error
      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end

    test "saves valid changes and exits edit mode", %{conn: conn} do
      medicine = insert(:medicine, name: "Original Name", brand_name: "Original Brand")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode
      render_click(view, "toggle_edit")

      # Make valid changes and save
      html =
        view
        |> form("#medicine-form", %{
          medicine: %{
            name: "Updated Name",
            brand_name: "Updated Brand"
          }
        })
        |> render_submit()

      # Should exit edit mode and show updated data
      assigns = get_assigns(view)
      assert assigns.edit_mode == false
      assert html =~ "Updated Name"
      assert html =~ "Updated Brand"

      # Verify database was updated
      updated_medicine = Medicines.get_medicine!(medicine.id)
      assert updated_medicine.name == "Updated Name"
      assert updated_medicine.brand_name == "Updated Brand"
    end

    test "handles save errors gracefully", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode
      render_click(view, "toggle_edit")

      # Try to save with invalid data (empty required field)
      html =
        view
        |> form("#medicine-form", %{medicine: %{name: ""}})
        |> render_submit()

      # Should stay in edit mode and show error
      assigns = get_assigns(view)
      assert assigns.edit_mode == true
      # The form should show validation errors
      assert html =~ "medicine-form"
    end
  end

  describe "photo management in edit mode" do
    test "removes photo in edit mode", %{conn: conn} do
      # Create test image files
      upload_path = Application.get_env(:medpack, :upload_path)
      test_file1_path = Path.join(upload_path, "photo1.jpg")
      test_file2_path = Path.join(upload_path, "photo2.jpg")

      File.mkdir_p!(Path.dirname(test_file1_path))
      File.mkdir_p!(Path.dirname(test_file2_path))

      # Create minimal JPEG file content
      jpeg_content =
        <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0xFF, 0xD9>>

      File.write!(test_file1_path, jpeg_content)
      File.write!(test_file2_path, jpeg_content)

      on_exit(fn ->
        File.rm(test_file1_path)
        File.rm(test_file2_path)
      end)

      medicine =
        insert(:medicine,
          name: "Test Medicine",
          photo_paths: ["/uploads/photo1.jpg", "/uploads/photo2.jpg"]
        )

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode
      render_click(view, "toggle_edit")

      # Remove first photo
      html = render_click(view, "remove_photo", %{"index" => "0"})

      # Should remove photo from the medicine
      updated_medicine = Medicines.get_medicine!(medicine.id)
      assert length(updated_medicine.photo_paths) == 1
      assert updated_medicine.photo_paths == ["/uploads/photo2.jpg"]

      # UI should update
      refute html =~ "src=\"/uploads/photo1.jpg\""
      assert html =~ "src=\"/uploads/photo2.jpg\""
    end

    test "handles photo upload configuration", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode
      render_click(view, "toggle_edit")

      # Check upload configuration
      assigns = get_assigns(view)
      assert assigns.uploads.photos.max_entries == 3
      assert assigns.uploads.photos.max_file_size == 10_000_000
      assert assigns.uploads.photos.auto_upload? == true
    end
  end

  describe "AI analysis integration" do
    test "triggers AI analysis for existing photos", %{conn: conn} do
      # Create a test image file
      upload_path = Application.get_env(:medpack, :upload_path)
      test_file_path = Path.join(upload_path, "test_photo.jpg")
      File.mkdir_p!(Path.dirname(test_file_path))
      # Create minimal JPEG file content
      jpeg_content =
        <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0xFF, 0xD9>>

      File.write!(test_file_path, jpeg_content)

      on_exit(fn ->
        File.rm(test_file_path)
      end)

      medicine =
        insert(:medicine,
          name: "Test Medicine",
          photo_paths: ["/uploads/test_photo.jpg"]
        )

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode
      render_click(view, "toggle_edit")

      # Trigger AI analysis
      render_click(view, "analyze_photos")

      # Force a render to ensure state is updated
      html = render(view)

      # Should show analyzing state
      assigns = get_assigns(view)
      assert assigns.analyzing == true
      assert html =~ "🤖 Analyzing photos..." or html =~ "Analyzing"
    end

    test "handles AI analysis completion", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Simulate AI analysis completion message
      analysis_result = %{
        name: "AI Detected Name",
        brand_name: "AI Detected Brand",
        active_ingredient: "AI Detected Ingredient"
      }

      send(view.pid, {:ai_analysis_complete, analysis_result})

      _html = render(view)

      # Should update form with AI results
      assigns = get_assigns(view)
      assert assigns.analyzing == false
      # The form should be populated with AI results when in edit mode
    end
  end

  describe "navigation and actions" do
    test "includes back to inventory link", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, _view, html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Should have back link
      assert html =~ "href=\"/inventory\""
      assert html =~ "← Back to Inventory" or html =~ "Back"
    end

    test "includes edit button in view mode", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, _view, html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Should have edit button
      assert html =~ "✏️ Edit Medicine" or html =~ "Edit"
    end

    test "includes analyze photos button when photos exist", %{conn: conn} do
      medicine =
        insert(:medicine,
          name: "Test Medicine",
          photo_paths: ["/uploads/photo1.jpg"]
        )

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode to see analyze button
      html = render_click(view, "toggle_edit")

      assert html =~ "🤖 Analyze Photos" or html =~ "Analyze"
    end
  end

  describe "error handling" do
    test "handles file upload errors gracefully", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode
      render_click(view, "toggle_edit")

      # Simulate upload error by sending error message
      # Suppress expected warning logs
      capture_log(fn ->
        send(view.pid, {:upload_error, "File too large"})
      end)

      _html = render(view)

      # Should handle error gracefully
      # Should stay in edit mode
      assigns = get_assigns(view)
      assert assigns.edit_mode == true
    end

    test "handles missing photos gracefully", %{conn: conn} do
      medicine =
        insert(:medicine,
          name: "Test Medicine",
          # File doesn't exist
          photo_paths: ["/uploads/nonexistent.jpg"]
        )

      {:ok, _view, html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Should not crash and handle missing file gracefully
      assert html =~ "Test Medicine"
    end
  end

  describe "responsive design and accessibility" do
    test "includes proper form labels and structure", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode to see form
      html = render_click(view, "toggle_edit")

      # Check form structure
      assert html =~ "Medicine Name"
      assert html =~ "Brand Name"
      assert html =~ "Dosage Form"
      assert html =~ "Active Ingredient"
      assert html =~ "required"
    end

    test "includes responsive design classes", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, _view, html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Check responsive layout
      assert html =~ "md:flex"
      assert html =~ "md:w-1/2"
      assert html =~ "max-w-4xl"
      assert html =~ "px-4 sm:px-6 lg:px-8"
    end

    test "includes proper image alt attributes", %{conn: conn} do
      medicine =
        insert(:medicine,
          name: "Test Medicine",
          photo_paths: ["/uploads/photo1.jpg"]
        )

      {:ok, _view, html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Should have proper alt attributes
      assert html =~ "alt=\"Test Medicine\""
    end
  end

  describe "real-time updates and file handling" do
    test "processes uploaded files and updates medicine", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine", photo_paths: [])

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode
      render_click(view, "toggle_edit")

      # Simulate file upload completion
      send(view.pid, {:process_uploaded_files})

      _html = render(view)

      # Should handle the upload processing
      assigns = get_assigns(view)
      assert assigns.edit_mode == true
    end

    test "updates progress during file upload", %{conn: conn} do
      medicine = insert(:medicine, name: "Test Medicine")

      {:ok, view, _html} = live(conn, ~p"/inventory/#{medicine.id}")

      # Enter edit mode
      render_click(view, "toggle_edit")

      # Check that upload progress is tracked
      assigns = get_assigns(view)
      assert assigns.upload_progress == 0
      assert assigns.analyzing == false
    end
  end
end
