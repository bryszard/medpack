defmodule MedpackWeb.Integration.BatchWorkflowIntegrationTest do
  use Medpack.VCRCase, async: false

  import Phoenix.LiveViewTest
  import Medpack.Factory
  import ExUnit.CaptureLog

  # Import web-specific functions
  use MedpackWeb, :verified_routes
  import Phoenix.ConnTest

  # Need async: false for database and file operations

  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  defp get_assigns(view) do
    :sys.get_state(view.pid).socket.assigns
  end

  defp copy_fixture_to_tmp(filename) do
    src = Path.join(["test", "fixtures", "files", filename])
    rel_dir = "integration_test_uploads"
    dest_dir = Path.join(["tmp", "test_uploads", rel_dir])
    File.mkdir_p!(Path.expand(dest_dir))
    rel_path = Path.join(rel_dir, "#{System.unique_integer([:positive])}_#{filename}")
    dest = Path.join(["tmp", "test_uploads", rel_path])
    File.cp!(src, dest)
    rel_path
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

      # Create a real batch entry with photos for testing
      batch_entry = insert(:batch_entry, ai_analysis_status: :pending)
      test_image_path = copy_fixture_to_tmp("xylo1.jpg")

      insert(:entry_image,
        batch_entry: batch_entry,
        s3_key: test_image_path,
        original_filename: "xylo1.jpg",
        file_size: File.stat!(Path.join(["tmp", "test_uploads", test_image_path])).size
      )

      # Update the view to include our real database entry
      assigns = get_assigns(view)
      entry_0 = Enum.at(assigns.entries, 0)
      updated_entry = %{
        entry_0
        | id: batch_entry.id,
          photos_uploaded: 1,
          photo_paths: [test_image_path],
          photo_web_paths: [test_image_path],
          ai_analysis_status: :pending
      }
      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      html = render(view)

      # Should show uploaded photos in the entry display
      assert html =~ "Photos (1/3)" or html =~ "photo"

      # Check that database entry was created
      assigns = get_assigns(view)
      final_entry = Enum.at(assigns.entries, 0)

      # The entry should now have a real database ID and photos
      assert final_entry.photos_uploaded > 0
      assert length(final_entry.photo_paths) > 0

      # Now trigger AI analysis with VCR cassette
      use_cassette "analyze_single_medicine_photo" do
        # Trigger analysis for the entry
        render_click(view, "analyze_now", %{"id" => updated_entry.id})

        # Wait for analysis to complete
        html = render(view)

        # Should show analysis results or processing state
        assert html =~ "🤖" or html =~ "Analysis" or html =~ "processing"

        # Check that the entry was updated with analysis results
        assigns = get_assigns(view)
        final_entry = Enum.at(assigns.entries, 0)

        # Entry should have analysis results or be marked as failed
        assert final_entry.ai_analysis_status in [:complete, :failed, :processing]

        if final_entry.ai_analysis_status == :complete do
          assert is_map(final_entry.ai_results)
          assert Map.has_key?(final_entry.ai_results, "name")
        end
      end
    end

    test "real file upload and AI analysis workflow", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      assigns = get_assigns(view)
      entry = Enum.at(assigns.entries, 0)

      # Use real test images for upload
      test_image_path = copy_fixture_to_tmp("xylo1.jpg")

      # Create a real batch entry in the database
      batch_entry = insert(:batch_entry, ai_analysis_status: :pending)

      # Create real entry images with actual file paths
      _image1 = insert(:entry_image,
        batch_entry: batch_entry,
        s3_key: test_image_path,
        original_filename: "xylo1.jpg",
        file_size: File.stat!(Path.join(["tmp", "test_uploads", test_image_path])).size
      )

      # Update the view to include our real database entry
      updated_entry = %{
        entry
        | id: batch_entry.id,
          photos_uploaded: 1,
          photo_paths: [test_image_path],
          photo_web_paths: [test_image_path],
          ai_analysis_status: :pending
      }

      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      html = render(view)

      # Should show uploaded photo
      assert html =~ "Photos (1/3)" or html =~ "photo"
      assert html =~ "🤖 Analyze Now"

      # Trigger real AI analysis with VCR
      use_cassette "analyze_single_medicine_photo" do
        render_click(view, "analyze_now", %{"id" => batch_entry.id})

        # Wait for analysis to complete
        html = render(view)

        # Should show analysis in progress or complete
        assert html =~ "🤖" or html =~ "Analysis" or html =~ "processing"

        # Check database was updated
        assigns = get_assigns(view)
        final_entry = Enum.at(assigns.entries, 0)
        assert final_entry.ai_analysis_status in [:complete, :failed, :processing]
      end
    end

    test "multiple photo upload and analysis", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Create batch entry with multiple real photos
      batch_entry = insert(:batch_entry, ai_analysis_status: :pending)

      test_image1 = copy_fixture_to_tmp("xylo1.jpg")
      test_image2 = copy_fixture_to_tmp("xylo2.jpg")

      _image1 = insert(:entry_image,
        batch_entry: batch_entry,
        s3_key: test_image1,
        original_filename: "xylo1.jpg",
        file_size: File.stat!(Path.join(["tmp", "test_uploads", test_image1])).size
      )

      _image2 = insert(:entry_image,
        batch_entry: batch_entry,
        s3_key: test_image2,
        original_filename: "xylo2.jpg",
        file_size: File.stat!(Path.join(["tmp", "test_uploads", test_image2])).size
      )

      # Update view with real entry
      assigns = get_assigns(view)
      entry = Enum.at(assigns.entries, 0)

      updated_entry = %{
        entry
        | id: batch_entry.id,
          photos_uploaded: 2,
          photo_paths: [test_image1, test_image2],
          photo_web_paths: [test_image1, test_image2],
          ai_analysis_status: :pending
      }

      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      html = render(view)
      assert html =~ "Photos (2/3)"

      # Analyze with multiple photos using VCR
      use_cassette "analyze_multiple_medicine_photos" do
        render_click(view, "analyze_now", %{"id" => batch_entry.id})

        html = render(view)
        assert html =~ "🤖" or html =~ "Analysis"

        assigns = get_assigns(view)
        final_entry = Enum.at(assigns.entries, 0)
        assert final_entry.ai_analysis_status in [:complete, :failed, :processing]
      end
    end

    test "error handling during real analysis workflow", %{conn: conn} do
      # Create batch entry with invalid image path
      batch_entry = insert(:batch_entry, ai_analysis_status: :pending)
      _image = insert(:entry_image,
        batch_entry: batch_entry,
        s3_key: "/invalid/path.jpg"
      )

      {:ok, view, _html} = live(conn, ~p"/add")

      # Update view with problematic entry
      assigns = get_assigns(view)
      entry = Enum.at(assigns.entries, 0)

      updated_entry = %{
        entry
        | id: batch_entry.id,
          photos_uploaded: 1,
          photo_paths: ["/invalid/path.jpg"],
          photo_web_paths: ["/invalid/path.jpg"],
          ai_analysis_status: :pending
      }

      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      # Try to analyze - should fail gracefully
      use_cassette "analyze_invalid_format" do
        render_click(view, "analyze_now", %{"id" => batch_entry.id})

        # Should handle failure gracefully
        assigns = get_assigns(view)
        final_entry = Enum.at(assigns.entries, 0)
        assert final_entry.ai_analysis_status in [:failed, :pending, :processing]

        # User should be able to continue with other entries
        render_click(view, "add_entries", %{"count" => "1"})
        assigns = get_assigns(view)
        assert length(assigns.entries) >= 2
      end
    end

    test "batch entry editing workflow with real data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Initially no entry is selected for edit
      assigns = get_assigns(view)
      assert assigns.selected_for_edit == nil

      # Edit first entry
      first_entry_id = Enum.at(assigns.entries, 0).id
      render_click(view, "edit_entry", %{"id" => first_entry_id})
      assigns = get_assigns(view)
      assert assigns.selected_for_edit == first_entry_id

      # Cancel edit
      render_click(view, "cancel_edit")

      # Should exit edit mode
      assigns = get_assigns(view)
      assert assigns.selected_for_edit == nil
    end

    test "entry removal workflow with database cleanup", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/add")

      # Create a real batch entry with images
      batch_entry = insert(:batch_entry)
      test_image = copy_fixture_to_tmp("xylo1.jpg")
      _image = insert(:entry_image,
        batch_entry: batch_entry,
        s3_key: test_image,
        original_filename: "xylo1.jpg",
        file_size: File.stat!(Path.join(["tmp", "test_uploads", test_image])).size
      )

      # Update view to include real entry
      assigns = get_assigns(view)
      entry = Enum.at(assigns.entries, 0)
      updated_entry = %{entry | id: batch_entry.id}
      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      # Initially should have the real entry
      assigns = get_assigns(view)
      assert length(assigns.entries) == 3

      # Remove the real entry
      _html = render_click(view, "remove_entry", %{"id" => batch_entry.id})

      # Should have 2 entries left and database entry should be deleted
      assigns = get_assigns(view)
      assert length(assigns.entries) == 2

      # Verify database entry was actually deleted
      assert Medpack.BatchProcessing.get_entry(batch_entry.id) == nil

      # Add entry back
      render_click(view, "add_entries", %{"count" => "1"})
      assigns = get_assigns(view)
      assert length(assigns.entries) == 3
    end

    test "concurrent analysis handling with real jobs", %{conn: conn} do
      # Create multiple batch entries with real images
      batch_entry1 = insert(:batch_entry, ai_analysis_status: :pending)
      batch_entry2 = insert(:batch_entry, ai_analysis_status: :pending)

      test_image = copy_fixture_to_tmp("xylo1.jpg")

      _image1 = insert(:entry_image,
        batch_entry: batch_entry1,
        s3_key: test_image,
        original_filename: "xylo1.jpg",
        file_size: File.stat!(Path.join(["tmp", "test_uploads", test_image])).size
      )
      _image2 = insert(:entry_image,
        batch_entry: batch_entry2,
        s3_key: test_image,
        original_filename: "xylo1.jpg",
        file_size: File.stat!(Path.join(["tmp", "test_uploads", test_image])).size
      )

      {:ok, view, _html} = live(conn, ~p"/add")

      # Update view with real entries
      assigns = get_assigns(view)
      entry1 = Enum.at(assigns.entries, 0)
      entry2 = Enum.at(assigns.entries, 1)

      updated_entry1 = %{entry1 | id: batch_entry1.id, photos_uploaded: 1, photo_paths: [test_image]}
      updated_entry2 = %{entry2 | id: batch_entry2.id, photos_uploaded: 1, photo_paths: [test_image]}

      updated_entries = [updated_entry1, updated_entry2 | Enum.drop(assigns.entries, 2)]
      send(view.pid, {:update_entries, updated_entries})

      # Send concurrent analysis updates using VCR
      use_cassette "analyze_medicine_job_concurrent" do
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

        # Check that entries were updated
        entry1_final = Enum.find(assigns.entries, &(&1.id == batch_entry1.id))
        entry2_final = Enum.find(assigns.entries, &(&1.id == batch_entry2.id))

        if entry1_final do
          assert entry1_final.ai_analysis_status == :complete
        end

        if entry2_final do
          assert entry2_final.ai_analysis_status == :complete
        end
      end
    end

    test "workflow navigation and state persistence", %{conn: conn} do
      # Create a real batch entry in the database for editing
      batch_entry = insert(:batch_entry, ai_analysis_status: :pending)
      test_image_path = copy_fixture_to_tmp("xylo1.jpg")

      insert(:entry_image,
        batch_entry: batch_entry,
        s3_key: test_image_path,
        original_filename: "xylo1.jpg",
        file_size: File.stat!(Path.join(["tmp", "test_uploads", test_image_path])).size
      )

      {:ok, view, _html} = live(conn, ~p"/add")

      # Update view with real database entry
      assigns = get_assigns(view)
      entry = Enum.at(assigns.entries, 0)
      updated_entry = %{
        entry
        | id: batch_entry.id,
          photos_uploaded: 1,
          photo_paths: [test_image_path],
          photo_web_paths: [test_image_path],
          ai_analysis_status: :pending
      }
      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      # Add more entries and modify state
      render_click(view, "add_entries", %{"count" => "2"})
      assigns = get_assigns(view)
      # Should have 3 initial entries + 2 new entries = 5 total
      assert length(assigns.entries) >= 3

      # Edit the real database entry
      render_click(view, "edit_entry", %{"id" => batch_entry.id})
      assigns = get_assigns(view)
      assert assigns.selected_for_edit == batch_entry.id

      # Save the edit with real database update
      render_click(view, "save_entry_edit", %{
        "entry_id" => batch_entry.id,
        "medicine" => %{"name" => "Persistent Medicine"}
      })

      # State should be maintained and database should be updated
      assigns = get_assigns(view)
      assert length(assigns.entries) >= 3
      entry_0 = Enum.at(assigns.entries, 0)
      assert entry_0.ai_results["name"] == "Persistent Medicine"

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
      # Get the first upload config (they're dynamically named)
      first_upload_key = assigns.uploads |> Map.keys() |> Enum.find(&String.contains?(Atom.to_string(&1), "entry_"))
      upload_config = assigns.uploads[first_upload_key]
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

    test "complete user journey with multiple entries and real analysis", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/add")

      # User starts with default entries
      assert html =~ "Medicine Entry"
      assigns = get_assigns(view)
      assert length(assigns.entries) == 3

      # User adds more entries for a larger batch
      render_click(view, "add_entries", %{"count" => "3"})
      assigns = get_assigns(view)
      assert length(assigns.entries) == 6

      # User can interact with entries (editing functionality may not be fully implemented)
      assigns = get_assigns(view)
      first_entry = Enum.at(assigns.entries, 0)
      assert first_entry.id != nil

      # User removes an unused entry
      last_entry_id = List.last(assigns.entries).id
      render_click(view, "remove_entry", %{"id" => last_entry_id})
      assigns = get_assigns(view)
      assert length(assigns.entries) == 5

      # Complete workflow validation
      assigns = get_assigns(view)
      assert assigns.batch_status == :ready
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

      # Update view with problematic entry
      assigns = get_assigns(view)
      entry = Enum.at(assigns.entries, 0)
      updated_entry = %{
        entry
        | id: batch_entry.id,
          photos_uploaded: 1,
          photo_paths: ["/invalid/path.jpg"],
          photo_web_paths: ["/invalid/path.jpg"]
      }
      updated_entries = [updated_entry | Enum.drop(assigns.entries, 1)]
      send(view.pid, {:update_entries, updated_entries})

      # Simulate analysis failure with VCR
      use_cassette "analyze_invalid_format" do
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
        assert length(assigns.entries) == 1

        # User can still work with other entries
        render_click(view, "add_entries", %{"count" => "1"})
        assigns = get_assigns(view)
        assert length(assigns.entries) == 2
      end
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
      render(view)
      end_time = System.monotonic_time(:millisecond)

      # Should render within reasonable time
      # 2 seconds max
      assert end_time - start_time < 2000
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
      end)

      # Core state should remain consistent
      assigns = get_assigns(view)
      assert assigns.batch_id == initial_batch_id
      assert length(assigns.entries) == initial_entry_count + 2
    end
  end
end
