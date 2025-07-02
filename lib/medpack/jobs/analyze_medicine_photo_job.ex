defmodule Medpack.Jobs.AnalyzeMedicinePhotoJob do
  @moduledoc """
  Background job for analyzing medicine photos using OpenAI Vision API.
  """

  use Oban.Worker, queue: :ai_analysis, max_attempts: 3

  alias Medpack.BatchProcessing
  alias Medpack.AI.ImageAnalyzer

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entry_id" => entry_id}}) do
    Logger.info("Starting medicine photo analysis for entry #{entry_id}")

    with {:ok, entry} <- get_entry(entry_id),
         {:ok, updated_entry} <- mark_as_processing(entry),
         {:ok, analysis_results} <- analyze_photo(updated_entry),
         {:ok, _final_entry} <- update_with_results(updated_entry, analysis_results) do
      Logger.info("Successfully analyzed medicine photo for entry #{entry_id}")
      broadcast_update(entry_id, :complete, analysis_results)
      :ok
    else
      {:error, :entry_not_found} ->
        Logger.error("Entry #{entry_id} not found")
        {:error, :entry_not_found}

      {:error, :no_photo} ->
        Logger.error("No photo found for entry #{entry_id}")
        mark_as_failed(entry_id, "No photo uploaded")
        {:error, :no_photo}

      {:error, reason} ->
        Logger.error("Analysis failed for entry #{entry_id}: #{inspect(reason)}")
        mark_as_failed(entry_id, "Analysis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_entry(entry_id) do
    case BatchProcessing.get_entry!(entry_id) do
      nil -> {:error, :entry_not_found}
      entry -> {:ok, entry}
    end
  rescue
    Ecto.NoResultsError -> {:error, :entry_not_found}
  end

  defp mark_as_processing(entry) do
    BatchProcessing.update_entry(entry, %{ai_analysis_status: :processing})
  end

  defp analyze_photo(entry) do
    case entry.photo_path do
      nil ->
        {:error, :no_photo}

      photo_identifier ->
        # Convert photo identifier to processable path/URL
        processable_path =
          if Medpack.FileManager.use_s3_storage?() do
            # For S3, get presigned URL for analysis
            Medpack.S3FileManager.get_presigned_url(photo_identifier)
          else
            # For local files, photo_identifier is already the full path
            photo_identifier
          end

        case processable_path do
          nil ->
            {:error, :failed_to_generate_presigned_url}

          path_or_url ->
            case ImageAnalyzer.analyze_medicine_photo(path_or_url) do
              {:ok, results} ->
                {:ok, results}

              {:error, reason} ->
                {:error, reason}
            end
        end
    end
  end

  defp update_with_results(entry, analysis_results) do
    BatchProcessing.update_analysis_results(entry, analysis_results)
  end

  defp mark_as_failed(entry_id, error_message) do
    case BatchProcessing.get_entry!(entry_id) do
      nil ->
        :ok

      entry ->
        BatchProcessing.mark_analysis_failed(entry, error_message)
        broadcast_update(entry_id, :failed, %{error: error_message})
    end
  rescue
    Ecto.NoResultsError -> :ok
  end

  defp broadcast_update(entry_id, status, data) do
    Phoenix.PubSub.broadcast(
      Medpack.PubSub,
      "batch_processing",
      {:analysis_update, %{entry_id: entry_id, status: status, data: data}}
    )
  end
end
