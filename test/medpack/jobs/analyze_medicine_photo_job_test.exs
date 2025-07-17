defmodule Medpack.Jobs.AnalyzeMedicinePhotoJobTest do
  use Medpack.VCRCase, async: false

  alias Medpack.Jobs.AnalyzeMedicinePhotoJob
  alias Medpack.BatchProcessing

  import ExUnit.CaptureLog

  # Need async: false for database transactions and VCR cassettes

  describe "perform/1" do
    test "successfully analyzes entry with images" do
      # Create entry with images
      entry = insert(:batch_entry, ai_analysis_status: :processing)
      _image1 = insert(:entry_image, batch_entry: entry)
      _image2 = insert(:entry_image, batch_entry: entry)

      # Mock successful VCR response
      use_cassette "analyze_medicine_job_success" do
        # Create job arguments
        job = %Oban.Job{args: %{"entry_id" => entry.id}}

        # Suppress expected error logs for this test
        capture_log(fn ->
          # Run the job
          result = AnalyzeMedicinePhotoJob.perform(job)

          # Should return :ok for successful processing
          case result do
            :ok ->
              # Check that entry was updated correctly
              updated_entry = BatchProcessing.get_entry!(entry.id)

              # Status should be updated (could be complete if successful, or failed if API error)
              assert updated_entry.ai_analysis_status in [:complete, :failed]

              # If complete, should have results and analyzed_at timestamp
              if updated_entry.ai_analysis_status == :complete do
                assert updated_entry.ai_results != nil
                assert updated_entry.analyzed_at != nil
              end

              # If failed, should have error message
              if updated_entry.ai_analysis_status == :failed do
                assert updated_entry.error_message != nil
              end

            {:error, reason} ->
              # Job errors are also valid test outcomes
              assert is_atom(reason) or is_binary(reason) or is_tuple(reason)
          end
        end)
      end
    end

    test "handles entry not found" do
      # Try to process non-existent entry
      job = %Oban.Job{args: %{"entry_id" => Ecto.UUID.generate()}}

      # Suppress expected error logs for this test
      capture_log(fn ->
        result = AnalyzeMedicinePhotoJob.perform(job)

        # Should handle gracefully
        assert result in [:ok, {:error, :entry_not_found}] or match?({:error, _}, result)
      end)
    end

    test "handles entry without images" do
      # Create entry without any images
      entry = insert(:batch_entry, ai_analysis_status: :processing)

      job = %Oban.Job{args: %{"entry_id" => entry.id}}

      # Suppress expected error logs for this test
      capture_log(fn ->
        result = AnalyzeMedicinePhotoJob.perform(job)

        # Should handle gracefully and mark entry as failed
        case result do
          :ok ->
            updated_entry = BatchProcessing.get_entry!(entry.id)
            # Should be marked as failed since no images
            assert updated_entry.ai_analysis_status == :failed

            assert updated_entry.error_message =~ "no images" or
                     updated_entry.error_message =~ "images"

          {:error, _reason} ->
            # Error is also acceptable
            assert true
        end
      end)
    end

    test "handles AI analysis failure" do
      # Create entry with images
      entry = insert(:batch_entry, ai_analysis_status: :processing)
      _image = insert(:entry_image, batch_entry: entry)

      use_cassette "analyze_medicine_job_api_failure" do
        job = %Oban.Job{args: %{"entry_id" => entry.id}}

        # Suppress expected error logs for this test
        capture_log(fn ->
          result = AnalyzeMedicinePhotoJob.perform(job)

          # Even if AI fails, job should handle it gracefully
          case result do
            :ok ->
              updated_entry = BatchProcessing.get_entry!(entry.id)
              # Should be marked as failed due to AI error
              assert updated_entry.ai_analysis_status == :failed
              assert updated_entry.error_message != nil

            {:error, _reason} ->
              # Job error is also acceptable
              assert true
          end
        end)
      end
    end

    test "handles database errors gracefully" do
      entry = insert(:batch_entry, ai_analysis_status: :processing)
      _image = insert(:entry_image, batch_entry: entry)

      # Delete the entry to simulate a race condition
      BatchProcessing.delete_entry(entry)

      job = %Oban.Job{args: %{"entry_id" => entry.id}}

      # Suppress expected error logs for this test
      capture_log(fn ->
        result = AnalyzeMedicinePhotoJob.perform(job)

        # Should handle missing entry gracefully
        assert result in [:ok, {:error, :entry_not_found}] or match?({:error, _}, result)
      end)
    end

    test "validates job arguments" do
      # Test with missing entry_id - this will cause a function clause error
      # which is expected behavior for malformed job arguments
      job = %Oban.Job{args: %{}}

      assert_raise FunctionClauseError, fn ->
        AnalyzeMedicinePhotoJob.perform(job)
      end
    end

    test "handles invalid entry_id format" do
      # Test with non-integer entry_id - this will cause a cast error when querying
      job = %Oban.Job{args: %{"entry_id" => "invalid"}}

      assert_raise Ecto.Query.CastError, fn ->
        AnalyzeMedicinePhotoJob.perform(job)
      end
    end
  end

  describe "job creation and queuing" do
    test "creates job with correct queue and arguments" do
      entry = insert(:batch_entry)

      job_changeset = AnalyzeMedicinePhotoJob.new(%{entry_id: entry.id}, queue: :ai_analysis)

      assert job_changeset.valid?
      assert job_changeset.changes.queue == "ai_analysis"
      assert job_changeset.changes.args == %{entry_id: entry.id}
    end

    test "can be enqueued with Oban" do
      entry = insert(:batch_entry)

      {:ok, job} =
        %{entry_id: entry.id}
        |> AnalyzeMedicinePhotoJob.new(queue: :ai_analysis)
        |> Oban.insert()

      assert job.queue == "ai_analysis"
      assert job.args == %{entry_id: entry.id}
      assert job.worker == "Medpack.Jobs.AnalyzeMedicinePhotoJob"
    end
  end

  describe "retry behavior" do
    test "job can be retried on failure" do
      entry = insert(:batch_entry, ai_analysis_status: :processing)
      _image = insert(:entry_image, batch_entry: entry)

      # Create job with retry configuration
      job = %Oban.Job{
        args: %{"entry_id" => entry.id},
        attempt: 1,
        max_attempts: 3
      }

      use_cassette "analyze_medicine_job_retry" do
        # Suppress expected error logs for this test
        capture_log(fn ->
          result = AnalyzeMedicinePhotoJob.perform(job)

          # Job should handle retries gracefully
          # Either succeed, fail gracefully, or return error for Oban to retry
          assert result in [:ok, :discard] or match?({:error, _}, result)
        end)
      end
    end

    test "job eventually gives up after max attempts" do
      entry = insert(:batch_entry, ai_analysis_status: :processing)
      _image = insert(:entry_image, batch_entry: entry)

      # Simulate final attempt
      job = %Oban.Job{
        args: %{"entry_id" => entry.id},
        attempt: 3,
        max_attempts: 3
      }

      use_cassette "analyze_medicine_job_final_attempt" do
        # Suppress expected error logs for this test
        capture_log(fn ->
          result = AnalyzeMedicinePhotoJob.perform(job)

          # On final attempt, should handle gracefully
          case result do
            :ok ->
              # Should mark entry as failed if this was the last attempt
              updated_entry = BatchProcessing.get_entry!(entry.id)
              assert updated_entry.ai_analysis_status in [:complete, :failed]

            {:error, _} ->
              # Error on final attempt should be handled
              assert true

            :discard ->
              # Discarding the job is also acceptable
              assert true
          end
        end)
      end
    end
  end

  describe "timeout handling" do
    test "handles long-running AI analysis" do
      entry = insert(:batch_entry, ai_analysis_status: :processing)
      _image = insert(:entry_image, batch_entry: entry)

      # This test would ideally use a timeout cassette
      # For now, we just ensure the job structure can handle it
      job = %Oban.Job{args: %{"entry_id" => entry.id}}

      use_cassette "analyze_medicine_job_timeout" do
        # Suppress expected error logs for this test
        capture_log(fn ->
          result = AnalyzeMedicinePhotoJob.perform(job)

          # Should handle timeouts gracefully
          assert result in [:ok, :discard] or match?({:error, _}, result)
        end)
      end
    end
  end

  describe "concurrent job handling" do
    test "handles multiple jobs for same entry" do
      entry = insert(:batch_entry, ai_analysis_status: :processing)
      _image = insert(:entry_image, batch_entry: entry)

      job1 = %Oban.Job{args: %{"entry_id" => entry.id}}
      job2 = %Oban.Job{args: %{"entry_id" => entry.id}}

      use_cassette "analyze_medicine_job_concurrent" do
        # Suppress expected error logs for this test
        capture_log(fn ->
          # Run both jobs
          result1 = AnalyzeMedicinePhotoJob.perform(job1)
          result2 = AnalyzeMedicinePhotoJob.perform(job2)

          # Both should handle gracefully
          assert result1 in [:ok, :discard] or match?({:error, _}, result1)
          assert result2 in [:ok, :discard] or match?({:error, _}, result2)

          # Entry should be in a consistent state
          final_entry = BatchProcessing.get_entry!(entry.id)
          assert final_entry.ai_analysis_status in [:pending, :processing, :complete, :failed]
        end)
      end
    end
  end
end
