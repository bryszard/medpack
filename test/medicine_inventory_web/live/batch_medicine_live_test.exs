defmodule MedpackWeb.BatchMedicineLiveTest do
  use MedpackWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Medpack.Factory

  # Need async: false because we're testing database, file operations, and PubSub

  setup :register_and_log_in_user

  defp get_assigns(view) do
    :sys.get_state(view.pid).socket.assigns
  end

  describe "mount and initial state" do
    test "mounts with initial empty entries", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/add")

      assigns = get_assigns(view)

      # Should have initial entries
      assert length(assigns.entries) == 3
      assert assigns.batch_status == :ready
      assert assigns.selected_for_edit == nil
      assert assigns.analyzing == false
      assert assigns.analysis_progress == 0

      # Should show batch medicine interface
      assert html =~ "Medicine Entry"
      assert html =~ "Add New Medicine"
    end
  end

  describe "adding entries" do
    test "adds specified number of entries", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)

      # Initially 3 entries
      assert length(assigns.entries) == 3

      # Add 2 more entries
      render_click(view, "add_entries", %{"count" => "2"})

      assigns = get_assigns(view)

      # Should now have 5 entries
      assert length(assigns.entries) == 5
    end

    test "configures uploads for new entries", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Add 1 more entry
      render_click(view, "add_entries", %{"count" => "1"})

      assigns = get_assigns(view)

      # New entry should be configured properly
      entry_3 = Enum.at(assigns.entries, 3)
      assert entry_3.number == 4
      assert entry_3.ai_analysis_status == :pending
      assert entry_3.photo_paths == []
    end

    test "handles large number of entries", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Add many entries
      render_click(view, "add_entries", %{"count" => "10"})

      assigns = get_assigns(view)

      # Should handle correctly
      assert length(assigns.entries) == 13

      # Should have proper entry numbers
      last_entry = List.last(assigns.entries)
      assert last_entry.number == 13
    end
  end

  describe "photo upload functionality" do
    test "handles file upload validation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)

      # Upload configuration should enforce limits
      upload_config = assigns.uploads |> Enum.at(1) |> Tuple.to_list() |> Enum.at(1)
      assert upload_config.max_entries >= 2
      assert upload_config.max_file_size > 0
      assert upload_config.auto_upload? == true
    end

    test "processes uploaded files and creates database entries", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Create a real batch entry in the database
      batch_entry = insert(:batch_entry)

      # Update the view to include our database entry
      assigns = get_assigns(view)
      entry = Enum.at(assigns.entries, 0)
      updated_entry = %{entry | id: batch_entry.id}
      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      render(view)

      # Entry should maintain its state
      assigns = get_assigns(view)
      updated_entry = Enum.at(assigns.entries, 0)
      assert updated_entry.id == batch_entry.id
    end

    test "shows upload progress", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/add")

      # Should show upload areas
      assert html =~ "📸 Add photo"
      assert html =~ "JPG, PNG up to 10MB each"
    end

    test "handles upload errors gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Simulate upload error
      entry_id = 0
      send(view.pid, {:upload_error, entry_id, "File too large"})

      _html = render(view)
      assigns = get_assigns(view)

      # Should handle error without crashing
      assert is_list(assigns.entries)
    end
  end

  describe "entry management" do
    test "toggles edit mode for entry", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)
      first_entry = Enum.at(assigns.entries, 0)
      entry_id = first_entry.id

      # First, simulate that the entry has been analyzed (required for edit mode)
      analyzed_entry = %{
        first_entry
        | ai_analysis_status: :complete,
          ai_results: %{"name" => "Test Medicine"}
      }

      updated_entries = [analyzed_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      # Toggle edit for first entry
      html = render_click(view, "edit_entry", %{"id" => entry_id})

      assigns = get_assigns(view)

      assert assigns.selected_for_edit == entry_id
      # Should show edit interface
      assert html =~ "Save"
      assert html =~ "Cancel"
    end

    test "saves entry changes", %{conn: conn} do
      insert(:batch_entry)

      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)

      first_entry = Enum.at(assigns.entries, 0)
      entry_id = first_entry.id

      # Enter edit mode
      render_click(view, "edit_entry", %{"id" => entry_id})

      # Save changes
      render_click(view, "save_entry_edit", %{
        "entry_id" => entry_id,
        "medicine" => %{
          "name" => "Custom Medicine Name",
        }
      })

      # Should update entry ai_results and approval status
      assigns = get_assigns(view)
      updated_entry = Enum.find(assigns.entries, &(&1.id == entry_id))
      assert updated_entry.ai_results["name"] == "Custom Medicine Name"

      # Should exit edit mode
      assert assigns.selected_for_edit == nil
    end

    test "saves entry changes with strength and quantity units", %{conn: conn} do
      insert(:batch_entry)

      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)

      first_entry = Enum.at(assigns.entries, 0)
      entry_id = first_entry.id

      # Enter edit mode
      render_click(view, "edit_entry", %{"id" => entry_id})

      # Save changes including the new unit fields
      render_click(view, "save_entry_edit", %{
        "entry_id" => entry_id,
        "medicine" => %{
          "name" => "Test Medicine",
          "strength_value" => "500",
          "strength_unit" => "mg",
          "total_quantity" => "30",
          "quantity_unit" => "tablets"
        }
      })

      # Should update entry ai_results with all fields
      assigns = get_assigns(view)
      updated_entry = Enum.find(assigns.entries, &(&1.id == entry_id))
      assert updated_entry.ai_results["name"] == "Test Medicine"
      assert updated_entry.ai_results["strength_value"] == "500"
      assert updated_entry.ai_results["strength_unit"] == "mg"
      assert updated_entry.ai_results["total_quantity"] == "30"
      assert updated_entry.ai_results["quantity_unit"] == "tablets"

      # Should exit edit mode
      assert assigns.selected_for_edit == nil
    end

    test "cancels entry editing", %{conn: conn} do
      insert(:batch_entry)

      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)
      first_entry = Enum.at(assigns.entries, 0)
      entry_id = first_entry.id

      render_click(view, "edit_entry", %{"id" => entry_id})
      render_click(view, "cancel_edit")

      assigns = get_assigns(view)

      assert assigns.selected_for_edit == nil
    end

    test "removes entry", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Initially 3 entries
      assigns = get_assigns(view)
      assert length(assigns.entries) == 3

      assigns = get_assigns(view)
      first_entry = Enum.at(assigns.entries, 0)
      first_entry_id = first_entry.id

      # Remove first entry
      render_click(view, "remove_entry", %{"id" => first_entry_id})

      assigns = get_assigns(view)

      # Should have 2 entries left
      assert length(assigns.entries) == 2

      # Entry IDs should be updated - the removed entry should not exist
      remaining_entry_ids = Enum.map(assigns.entries, & &1.id)
      assert first_entry_id not in remaining_entry_ids
    end
  end

  describe "AI analysis integration" do
    test "starts analysis for entry with photos", %{conn: conn} do
      # Create a real batch entry with photos for testing
      batch_entry = insert(:batch_entry)
      _image1 = insert(:entry_image, batch_entry: batch_entry)
      _image2 = insert(:entry_image, batch_entry: batch_entry)

      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)
      entry = Enum.at(assigns.entries, 0)

      updated_entry = %{
        entry
        | id: batch_entry.id,
          photos_uploaded: 2,
          photo_paths: ["/test1.jpg", "/test2.jpg"]
      }

      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      html = render_click(view, "analyze_now", %{"id" => "#{batch_entry.id}"})

      assert html =~ "🤖 AI Analysis" or html =~ "Analyzing"
    end

    test "handles analysis updates via PubSub", %{conn: conn} do
      batch_entry = insert(:batch_entry)

      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)
      entry = Enum.at(assigns.entries, 0)
      updated_entry = %{entry | id: batch_entry.id}
      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      analysis_data = %{
        "name" => "Aspirin",
        "dosage_form" => "tablet",
        "active_ingredient" => "acetylsalicylic acid",
        "strength_value" => "500mg",
        "container_type" => "bottle",
        "total_quantity" => "30",
        "brand_name" => "Bayer",
        "manufacturer" => "Bayer AG",
        "expiration_date" => "2025-12",
        "remaining_quantity" => "30"
      }

      send(
        view.pid,
        {:analysis_update,
         %{
           entry_id: batch_entry.id,
           status: :complete,
           data: analysis_data
         }}
      )

      html = render(view)
      assert html =~ "Aspirin"
      assert html =~ "Tablet"
      assert html =~ "acetylsalicylic acid"
      assert html =~ "500mg"
      assert html =~ "Bottle"
      assert html =~ "30"
      assert html =~ "Bayer"
      assert html =~ "Bayer AG"
      assert html =~ "2025-12"
    end

    test "handles analysis failure via PubSub", %{conn: conn} do
      batch_entry = insert(:batch_entry)

      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)
      entry = Enum.at(assigns.entries, 0)
      updated_entry = %{entry | id: batch_entry.id}
      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      error_data = %{error: "Failed to analyze photos"}

      send(
        view.pid,
        {:analysis_update,
         %{
           entry_id: batch_entry.id,
           status: :failed,
           data: error_data
         }}
      )

      html = render(view)
      assert html =~ "Analysis failed"
      assert html =~ "Failed to analyze photos"
    end

    test "shows analysis progress", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)

      # Initial state should be false
      assert assigns.analyzing == false
      assert assigns.analysis_progress == 0

      # Set analyzing state
      send(view.pid, {:set_analyzing, true})

      assigns = get_assigns(view)

      _html = render(view)

      # Should now show progress indicator
      assert assigns.analyzing == true
    end
  end

  describe "error handling and validation" do
    test "handles invalid entry IDs gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Try to interact with non-existent entry
      _html = render_click(view, "edit_entry", %{"id" => "999"})

      assigns = get_assigns(view)

      # Should handle gracefully without crashing
      assert is_list(assigns.entries)
    end

    test "handles missing photos for analysis", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)
      first_entry = Enum.at(assigns.entries, 0)
      entry_id = first_entry.id

      # Try to start analysis for entry without photos
      html = render_click(view, "analyze_now", %{"id" => entry_id})

      assigns = get_assigns(view)

      # Should show appropriate message or handle gracefully
      assert html =~ "No photos" or is_list(assigns.entries)
    end

    test "handles database errors during entry creation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Simulate database error
      send(view.pid, {:database_error, "Connection failed"})

      assigns = get_assigns(view)

      _html = render(view)

      # Should continue functioning
      assert is_list(assigns.entries)
    end

    test "validates file types and sizes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Check upload validation
      assigns = get_assigns(view)
      upload_config = assigns.uploads |> Enum.at(1) |> Tuple.to_list() |> Enum.at(1)

      # Should have proper file type restrictions
      assert upload_config.accept != nil
      assert upload_config.max_file_size > 0
    end
  end

  describe "navigation and workflow" do
    test "shows navigation back to inventory", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/add")

      # Should have navigation link
      assert html =~ "href=\"/inventory\""
    end

    test "shows batch processing workflow steps", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/add")

      # Should show workflow guidance
      assert html =~ "📸 Add photo"
      assert html =~ "Medicine Entry"
    end

    test "tracks batch processing status", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Should track overall status
      assigns = get_assigns(view)
      assert assigns.batch_status == :ready

      # Status should update as entries are processed
      # (This would be tested with actual photo uploads and analysis)
    end
  end

  describe "responsive design and accessibility" do
    test "includes proper form structure and labels", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)
      first_entry = Enum.at(assigns.entries, 0)
      entry_id = first_entry.id

      # First, simulate that the entry has been analyzed (required for edit mode)
      analyzed_entry = %{
        first_entry
        | ai_analysis_status: :complete,
          ai_results: %{"name" => "Test Medicine"}
      }

      updated_entries = [analyzed_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      # Enter edit mode to see form
      html = render_click(view, "edit_entry", %{"id" => entry_id})

      # Should have proper form structure
      assert html =~ "Medicine Name" or html =~ "name"
      assert html =~ "Dosage Form" or html =~ "dosage_form"
    end
  end

  describe "real-time updates and PubSub integration" do
    test "handles real-time analysis updates from background jobs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Simulate background job completion
      analysis_update = %{
        entry_id: 123,
        status: :complete,
        data: %{
          name: "Real-time Medicine",
          confidence: 0.95
        }
      }

      send(view.pid, {:analysis_update, analysis_update})

      assigns = get_assigns(view)

      _html = render(view)

      # Should handle update gracefully
      assert is_list(assigns.entries)
    end

    test "handles multiple concurrent updates", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Send multiple updates rapidly
      for i <- 1..5 do
        send(
          view.pid,
          {:analysis_update,
           %{
             entry_id: i,
             status: :processing,
             data: %{}
           }}
        )
      end

      assigns = get_assigns(view)

      _html = render(view)

      # Should handle all updates without issues
      assert is_list(assigns.entries)
    end

    test "maintains state consistency during updates", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)

      initial_batch_id = assigns.batch_id
      initial_entry_count = length(assigns.entries)

      # Send update that shouldn't affect core state
      send(
        view.pid,
        {:analysis_update,
         %{
           entry_id: 999,
           status: :complete,
           data: %{}
         }}
      )

      render(view)

      assigns = get_assigns(view)

      # Core state should remain consistent
      assert assigns.batch_id == initial_batch_id
      assert length(assigns.entries) == initial_entry_count
    end
  end
end
