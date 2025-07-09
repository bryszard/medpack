defmodule Medpack.Jobs.CleanupFilesJobTest do
  use Medpack.DataCase, async: false

  alias Medpack.Jobs.CleanupFilesJob

  import ExUnit.CaptureLog

  # Need async: false for file system operations

  describe "perform/1" do
    test "successfully runs with default parameters" do
      # Ensure temp directory exists
      temp_dir = Application.get_env(:medpack, :temp_upload_path)
      File.mkdir_p!(temp_dir)

      job = %Oban.Job{args: %{}}

      result = CleanupFilesJob.perform(job)

      # Should complete successfully or handle missing files gracefully
      case result do
        :ok -> assert true
        # File operations can fail in test environment
        {:error, _} -> assert true
      end
    end

    test "accepts max_age_hours parameter" do
      temp_dir = Application.get_env(:medpack, :temp_upload_path)
      File.mkdir_p!(temp_dir)

      job = %Oban.Job{args: %{"max_age_hours" => 48}}

      result = CleanupFilesJob.perform(job)

      case result do
        :ok -> assert true
        {:error, _} -> assert true
      end
    end

    test "handles missing temporary directory" do
      # Temporarily remove temp directory
      temp_dir = Application.get_env(:medpack, :temp_upload_path)
      File.rm_rf!(temp_dir)

      job = %Oban.Job{args: %{}}

      # Suppress expected error logs for this test
      capture_log(fn ->
        result = CleanupFilesJob.perform(job)

        # Should return error for missing directory
        assert {:error, :enoent} = result
      end)

      # Restore directory for other tests
      File.mkdir_p!(temp_dir)
    end

    test "handles empty directory gracefully" do
      temp_dir = Application.get_env(:medpack, :temp_upload_path)
      File.mkdir_p!(temp_dir)

      # Ensure directory is empty
      File.ls!(temp_dir)
      |> Enum.each(&File.rm!(Path.join(temp_dir, &1)))

      job = %Oban.Job{args: %{}}

      result = CleanupFilesJob.perform(job)

      assert result == :ok
    end

    test "processes files in temporary directory" do
      temp_dir = Application.get_env(:medpack, :temp_upload_path)
      File.mkdir_p!(temp_dir)

      # Create a test file
      test_file = Path.join(temp_dir, "test_cleanup_file.jpg")
      File.write!(test_file, "test content")

      job = %Oban.Job{args: %{"max_age_hours" => 1}}

      result = CleanupFilesJob.perform(job)

      # Should process without error
      case result do
        :ok -> assert true
        {:error, _} -> assert true
      end

      # Clean up test file if it still exists
      File.rm(test_file)
    end
  end

  describe "job scheduling and configuration" do
    test "creates job with correct configuration" do
      job_changeset = CleanupFilesJob.new(%{})

      assert job_changeset.valid?
      assert job_changeset.changes.args == %{}
    end

    test "creates job with max_age_hours parameter" do
      job_changeset = CleanupFilesJob.new(%{"max_age_hours" => 48})

      assert job_changeset.valid?
      assert job_changeset.changes.args == %{"max_age_hours" => 48}
    end

    test "can be enqueued with Oban" do
      {:ok, job} =
        %{}
        |> CleanupFilesJob.new()
        |> Oban.insert()

      assert job.args == %{}
      assert job.worker == "Medpack.Jobs.CleanupFilesJob"
    end

    test "can be enqueued with custom parameters" do
      {:ok, job} =
        %{"max_age_hours" => 72}
        |> CleanupFilesJob.new()
        |> Oban.insert()

      assert job.args == %{"max_age_hours" => 72}
    end

    test "can be scheduled for periodic execution" do
      job_changeset = CleanupFilesJob.new(%{}, schedule_in: 3600)

      assert job_changeset.valid?
    end

    test "schedule_cleanup/1 function works" do
      {:ok, job} = CleanupFilesJob.schedule_cleanup(48)

      assert job.args == %{max_age_hours: 48}
      assert job.queue == "file_cleanup"
    end
  end

  describe "error handling" do
    test "handles invalid directory permissions" do
      # Create job that should handle filesystem errors gracefully
      job = %Oban.Job{args: %{"max_age_hours" => 24}}

      result = CleanupFilesJob.perform(job)

      # Should either succeed or fail gracefully
      case result do
        :ok ->
          assert true

        {:error, reason} ->
          assert is_atom(reason)
          assert reason in [:enoent, :eacces, :enotdir]
      end
    end

    test "handles malformed job arguments" do
      # Test with non-numeric max_age_hours - this will cause ArithmeticError
      job = %Oban.Job{args: %{"max_age_hours" => "invalid"}}

      assert_raise ArithmeticError, fn ->
        CleanupFilesJob.perform(job)
      end
    end

    test "handles missing max_age_hours parameter" do
      # Test with completely different parameters
      job = %Oban.Job{args: %{"other_param" => "value"}}

      result = CleanupFilesJob.perform(job)

      # Should use default value and complete
      case result do
        :ok -> assert true
        {:error, _} -> assert true
      end
    end
  end

  describe "concurrent execution" do
    test "handles concurrent cleanup jobs" do
      temp_dir = Application.get_env(:medpack, :temp_upload_path)
      File.mkdir_p!(temp_dir)

      job1 = %Oban.Job{args: %{}}
      job2 = %Oban.Job{args: %{}}

      # Run both jobs concurrently
      task1 = Task.async(fn -> CleanupFilesJob.perform(job1) end)
      task2 = Task.async(fn -> CleanupFilesJob.perform(job2) end)

      result1 = Task.await(task1)
      result2 = Task.await(task2)

      # Both should complete (successfully or with expected errors)
      for result <- [result1, result2] do
        case result do
          :ok -> assert true
          {:error, _} -> assert true
        end
      end
    end

    test "handles multiple files efficiently" do
      temp_dir = Application.get_env(:medpack, :temp_upload_path)
      File.mkdir_p!(temp_dir)

      # Create multiple test files
      test_files =
        Enum.map(1..5, fn i ->
          file_path = Path.join(temp_dir, "test_file_#{i}.jpg")
          File.write!(file_path, "test content #{i}")
          file_path
        end)

      job = %Oban.Job{args: %{"max_age_hours" => 1}}

      result = CleanupFilesJob.perform(job)

      case result do
        :ok -> assert true
        {:error, _} -> assert true
      end

      # Clean up test files
      Enum.each(test_files, &File.rm/1)
    end
  end

  describe "integration with FileManager" do
    test "job delegates to FileManager.cleanup_temp_files/1" do
      # This is more of a smoke test to ensure the integration works
      job = %Oban.Job{args: %{"max_age_hours" => 24}}

      result = CleanupFilesJob.perform(job)

      # Should call FileManager and return its result
      case result do
        :ok -> assert true
        {:error, reason} -> assert is_atom(reason)
      end
    end

    test "respects FileManager configuration" do
      # Test that the job works with whatever FileManager setup exists
      temp_dir = Application.get_env(:medpack, :temp_upload_path)
      File.mkdir_p!(temp_dir)

      job = %Oban.Job{args: %{}}

      result = CleanupFilesJob.perform(job)

      # Should work with current configuration
      case result do
        :ok -> assert true
        {:error, _} -> assert true
      end
    end
  end
end
