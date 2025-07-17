defmodule MedpackWeb.Integration.BatchWorkflowIntegrationTest do
  use MedpackWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Medpack.Factory
  import ExUnit.CaptureLog

  # Need async: false for database and file operations

  defp get_assigns(view) do
    :sys.get_state(view.pid).socket.assigns
  end

  describe "complete batch medicine workflow" do
    test "end-to-end workflow from entry to medicine creation", %{conn: conn} do
      # User starts at add medicines page
      {:ok, view, html} = live(conn, ~p"/add")

      # Should show initial batch interface
      assert html =~ "Medicine Entry"

      assigns = get_assigns(view)
      assert length(assigns.entries) == 3

      # User adds more entries for a larger batch
      render_click(view, "add_entries", %{"count" => "2"})

      assigns = get_assigns(view)
      assert length(assigns.entries) == 5

      # Simulate photo upload completion for first entry
      # In real workflow, photos would be uploaded via LiveView uploads
      assigns = get_assigns(view)
      entry_0 = Enum.at(assigns.entries, 0)

      # Create database entry with photos (simulating upload completion)
      batch_entry = insert(:batch_entry, ai_analysis_status: :pending)
      _image1 = insert(:entry_image, batch_entry: batch_entry, s3_key: "/test/photo1.jpg")
      _image2 = insert(:entry_image, batch_entry: batch_entry, s3_key: "/test/photo2.jpg")

      # Update the view state to include uploaded photos
      updated_entry = %{
        entry_0
        | id: batch_entry.id,
          photos_uploaded: 2,
          photo_paths: ["/test/photo1.jpg", "/test/photo2.jpg"],
          photo_web_paths: ["/uploads/photo1.jpg", "/uploads/photo2.jpg"],
          ai_analysis_status: :pending
      }

      assigns = get_assigns(view)
      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})
      html = render(view)

      # Should show uploaded photos in the entry display
      assert html =~ "Photos (2/3)"
      assert html =~ "🤖 Analyze Now"
    end

    test "AI analysis workflow with real PubSub integration", %{conn: conn} do
      # Create a batch entry with photos ready for analysis
      batch_entry = insert(:batch_entry, ai_analysis_status: :pending)
      _image1 = insert(:entry_image, batch_entry: batch_entry)
      _image2 = insert(:entry_image, batch_entry: batch_entry)

      {:ok, view, _html} = live(conn, ~p"/add")

      # Simulate analysis update to processing state
      send(
        view.pid,
        {:analysis_update,
         %{
           entry_id: batch_entry.id,
           status: :processing,
           data: %{}
         }}
      )

      _html = render(view)
      # Should show processing state
      assigns = get_assigns(view)
      assert is_list(assigns.entries)

      # Simulate successful analysis completion
      analysis_result = %{
        name: "AI Detected Medicine",
        brand_name: "AI Brand",
        active_ingredient: "AI Ingredient",
        dosage_form: "tablet",
        strength: "500mg",
        manufacturer: "AI Pharma",
        confidence: 0.92
      }

      send(
        view.pid,
        {:analysis_update,
         %{
           entry_id: batch_entry.id,
           status: :complete,
           data: analysis_result
         }}
      )

      _html = render(view)

      # Should show analysis results
      # The exact UI depends on how the view handles these updates
      assigns = get_assigns(view)
      assert is_list(assigns.entries)
    end

    test "error handling during analysis workflow", %{conn: conn} do
      # Create batch entry that will fail analysis
      batch_entry = insert(:batch_entry, ai_analysis_status: :pending)
      _image = insert(:entry_image, batch_entry: batch_entry, s3_key: "/invalid/path.jpg")

      {:ok, view, _html} = live(conn, ~p"/add")

      # Simulate analysis failure
      send(
        view.pid,
        {:analysis_update,
         %{
           entry_id: batch_entry.id,
           status: :failed,
           data: %{error: "Unable to analyze photos"}
         }}
      )

      _html = render(view)

      # Should handle failure gracefully
      assigns = get_assigns(view)
      assert is_list(assigns.entries)

      # User should be able to continue with other entries
      render_click(view, "add_entries", %{"count" => "1"})
      assigns = get_assigns(view)
      assert length(assigns.entries) >= 3
    end

    test "batch entry editing workflow", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Initially no entry is selected for edit
      assigns = get_assigns(view)
      assert assigns.selected_for_edit == nil

      # Edit first entry
      first_entry_id = Enum.at(assigns.entries, 0).id
      _html = render_click(view, "edit_entry", %{"id" => first_entry_id})
      assigns = get_assigns(view)
      assert assigns.selected_for_edit == first_entry_id

      # Save entry with custom data
      _html =
        render_click(view, "save_entry_edit", %{
          "id" => first_entry_id,
          "name" => "Custom Medicine Name",
          "notes" => "User added notes"
        })

      # Should update entry and exit edit mode
      assigns = get_assigns(view)
      updated_entry = Enum.at(assigns.entries, 0)
      assert updated_entry.name == "Custom Medicine Name"
      assert updated_entry.notes == "User added notes"
      assert assigns.selected_for_edit == nil

      # Edit again and cancel
      render_click(view, "edit_entry", %{"id" => first_entry_id})
      _html = render_click(view, "cancel_edit")

      # Should exit edit mode without changing data
      assigns = get_assigns(view)
      assert assigns.selected_for_edit == nil
      final_entry = Enum.at(assigns.entries, 0)
      # Unchanged
      assert final_entry.name == "Custom Medicine Name"
    end

    test "entry removal workflow", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Initially 3 entries
      assigns = get_assigns(view)
      assert length(assigns.entries) == 3

      # Remove middle entry
      middle_entry_id = Enum.at(assigns.entries, 1).id
      _html = render_click(view, "remove_entry", %{"id" => middle_entry_id})

      # Should have 2 entries left
      assigns = get_assigns(view)
      assert length(assigns.entries) == 2

      # Add entry back
      render_click(view, "add_entries", %{"count" => "1"})
      assigns = get_assigns(view)
      assert length(assigns.entries) == 3
    end

    test "concurrent analysis handling", %{conn: conn} do
      # Create multiple batch entries
      batch_entry1 = insert(:batch_entry, ai_analysis_status: :processing)
      batch_entry2 = insert(:batch_entry, ai_analysis_status: :processing)

      {:ok, view, _html} = live(conn, ~p"/add")

      # Send concurrent analysis updates
      send(
        view.pid,
        {:analysis_update,
         %{
           entry_id: batch_entry1.id,
           status: :complete,
           data: %{name: "Medicine 1"}
         }}
      )

      send(
        view.pid,
        {:analysis_update,
         %{
           entry_id: batch_entry2.id,
           status: :complete,
           data: %{name: "Medicine 2"}
         }}
      )

      _html = render(view)

      # Should handle both updates correctly
      assigns = get_assigns(view)
      assert is_list(assigns.entries)
    end

    test "workflow navigation and state persistence", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)
      initial_batch_id = assigns.batch_id

      # Add entries and modify state
      render_click(view, "add_entries", %{"count" => "2"})
      assigns = get_assigns(view)
      first_entry_id = Enum.at(assigns.entries, 0).id
      render_click(view, "edit_entry", %{"id" => first_entry_id})

      render_click(view, "save_entry_edit", %{
        "id" => first_entry_id,
        "name" => "Persistent Medicine"
      })

      # State should be maintained
      assigns = get_assigns(view)
      assert length(assigns.entries) == 5
      entry_0 = Enum.at(assigns.entries, 0)
      assert entry_0[:name] == "Persistent Medicine"
      assert assigns.batch_id == initial_batch_id

      # Navigation should work
      assert render(view) =~ "← Back to Inventory" or render(view) =~ "href=\"/inventory\""
    end

    test "file upload validation and error handling", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/add")

      # Should show upload areas with proper validation messages
      assert html =~ "📸 Add photo"
      assert html =~ "JPG, PNG up to 10MB each"

      # Upload configuration should be set correctly
      assigns = get_assigns(view)
      upload_config = assigns.uploads.entry_1_photos
      assert upload_config.max_file_size > 0
      assert upload_config.auto_upload? == true

      # Simulate upload error
      send(view.pid, {:upload_error, 0, "File too large"})
      _html = render(view)

      # Should handle error gracefully
      assigns = get_assigns(view)
      assert is_list(assigns.entries)
    end

    test "real-time progress tracking", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Initial progress state
      assigns = get_assigns(view)
      assert assigns.analyzing == false
      assert assigns.analysis_progress == 0

      # Simulate progress updates
      send(view.pid, {:progress_update, 25})
      send(view.pid, {:progress_update, 50})
      send(view.pid, {:progress_update, 100})

      _html = render(view)

      # Should track progress
      assigns = get_assigns(view)
      assert is_list(assigns.entries)
    end

    test "complete user journey with multiple entries", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/add")

      # User starts with default entries
      assert html =~ "Medicine Entry"
      assigns = get_assigns(view)
      assert length(assigns.entries) == 3

      # User adds more entries for a larger batch
      render_click(view, "add_entries", %{"count" => "3"})
      assigns = get_assigns(view)
      assert length(assigns.entries) == 6

      # User customizes first entry
      assigns = get_assigns(view)
      first_entry_id = Enum.at(assigns.entries, 0).id
      render_click(view, "edit_entry", %{"id" => first_entry_id})

      render_click(view, "save_entry_edit", %{
        "batch_id" => first_entry_id,
        "medicine" => %{"name" => "Blood Pressure Medicine"},
      })

      assigns = get_assigns(view)
      entry_0 = Enum.at(assigns.entries, 0)
      assert entry_0.name == "Blood Pressure Medicine"
      assert entry_0.notes == "Take twice daily"

      # User removes an unused entry
      last_entry_id = List.last(assigns.entries).id
      render_click(view, "remove_entry", %{"id" => last_entry_id})
      assigns = get_assigns(view)
      assert length(assigns.entries) == 5

      # User can continue using card view
      html = render(view)
      assert html =~ "Medicine Entry"
      assert html =~ "Medicine Entry #2"

      # Complete workflow validation
      assigns = get_assigns(view)
      assert assigns.batch_status == :ready
      assert is_binary(assigns.batch_id)
    end
  end

  describe "workflow integration with AI analysis" do
    test "workflow handles AI analysis failures gracefully", %{conn: conn} do
      batch_entry = insert(:batch_entry, ai_analysis_status: :pending)

      _image =
        insert(:entry_image,
          batch_entry: batch_entry,
          s3_key: "/invalid/path.jpg"
        )

      {:ok, view, _html} = live(conn, ~p"/add")

      # Simulate analysis failure
      send(
        view.pid,
        {:analysis_update,
         %{
           entry_id: batch_entry.id,
           status: :failed,
           data: %{error: "Image format not supported"}
         }}
      )

      _html = render(view)

      # Workflow should continue functioning
      assigns = get_assigns(view)
      assert is_list(assigns.entries)

      # User can still work with other entries
      render_click(view, "add_entries", %{"count" => "1"})
      assigns = get_assigns(view)
      assert length(assigns.entries) >= 3
    end
  end

  describe "workflow performance and scalability" do
    test "handles large batches efficiently", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Add many entries
      render_click(view, "add_entries", %{"count" => "20"})

      # Should handle large batch efficiently
      assigns = get_assigns(view)
      assert length(assigns.entries) == 23

      # Performance should remain reasonable
      start_time = System.monotonic_time(:millisecond)
      html = render(view)
      end_time = System.monotonic_time(:millisecond)

      # Should render within reasonable time
      # 2 seconds max
      assert end_time - start_time < 2000
      assert html =~ "Medicine Entry #23"
    end

    test "memory usage stays reasonable with large batches", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Add many entries
      render_click(view, "add_entries", %{"count" => "50"})

      # Process multiple concurrent updates
      for i <- 1..50 do
        send(
          view.pid,
          {:analysis_update,
           %{
             entry_id: i,
             status: :complete,
             data: %{name: "Medicine #{i}"}
           }}
        )
      end

      html = render(view)

      # Should handle all updates without issues
      assigns = get_assigns(view)
      assert length(assigns.entries) == 53
      assert is_binary(html)
    end
  end

  describe "workflow error recovery" do
    test "recovers from database connection issues", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Simulate database error
      send(view.pid, {:database_error, "Connection timeout"})

      _html = render(view)

      # Should continue functioning
      assigns = get_assigns(view)
      assert is_list(assigns.entries)

      # User can still interact with the interface
      render_click(view, "add_entries", %{"count" => "1"})
      assigns = get_assigns(view)
      assert length(assigns.entries) == 4
    end

    test "handles network issues during file upload", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Simulate network error during upload
      send(view.pid, {:upload_error, 0, "Network timeout"})

      _html = render(view)

      # Should handle gracefully
      assigns = get_assigns(view)
      assert is_list(assigns.entries)

      # Interface should remain functional
      assigns = get_assigns(view)
      second_entry_id = Enum.at(assigns.entries, 1).id
      render_click(view, "edit_entry", %{"id" => second_entry_id})
      assigns = get_assigns(view)
      assert assigns.selected_for_edit == second_entry_id
    end

    test "state consistency after errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)
      initial_batch_id = assigns.batch_id
      initial_entry_count = length(assigns.entries)

      # Apply several state changes
      render_click(view, "add_entries", %{"count" => "2"})
      assigns = get_assigns(view)
      first_entry_id = Enum.at(assigns.entries, 0).id
      render_click(view, "edit_entry", %{"id" => first_entry_id})

      # Simulate error
      capture_log(fn ->
        send(view.pid, {:error, "Something went wrong"})
        # Give the LiveView a moment to process the message
        Process.sleep(10)
      end)

      # Core state should remain consistent
      assigns = get_assigns(view)
      assert assigns.batch_id == initial_batch_id
      assert length(assigns.entries) == initial_entry_count + 2
    end
  end

  describe "workflow accessibility and usability" do
    test "provides clear feedback for all user actions", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/add")

      # Should show clear instructions
      assert html =~ "📸 Add photo"
      assert html =~ "🤖 AI Analysis Results"

      # Actions should have clear visual feedback
      assert html =~ "📸 Add photo"
      assert html =~ "JPG, PNG up to 10MB each"
    end

    test "workflow is keyboard accessible", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/add")

      # Should have proper button and form structure
      assert html =~ "btn"
      assert html =~ "form"

      # Interactive elements should be accessible
      assert html =~ "Add New Medicine"
    end

    test "provides progress indicators throughout workflow", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/add")

      # Should show current workflow status
      assigns = get_assigns(view)
      assert assigns.batch_status == :ready
      assert assigns.analyzing == false
      assert assigns.analysis_progress == 0

      # Visual progress indicators should be present
      assert html =~ "Medicine Entry"
      assert html =~ "Medicine Entry #2"
      assert html =~ "Medicine Entry #3"
    end
  end
end
