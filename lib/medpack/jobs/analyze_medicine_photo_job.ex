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
        # Convert reason to a simple string for Oban serialization
        error_message =
          case reason do
            {:file_not_found, path} ->
              "File not found: #{path}"

            :timeout ->
              "OpenAI API timeout - please try again"

            :max_retries_exceeded ->
              "OpenAI API failed after multiple retries - please try again later"

            :api_call_failed ->
              "OpenAI API call failed - please check your connection and try again"

            atom when is_atom(atom) ->
              "#{atom}"

            binary when is_binary(binary) ->
              binary

            _ ->
              "Analysis failed: #{inspect(reason)}"
          end

        mark_as_failed(entry_id, error_message)
        {:error, reason}
    end
  end

  defp get_entry(entry_id) do
    case BatchProcessing.get_entry_with_images!(entry_id) do
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
    Logger.info("Analyzing photos for entry #{entry.id}, images count: #{length(entry.images)}")

    case entry.images do
      [] ->
        Logger.error("No images found for entry #{entry.id}")
        {:error, :no_photo}

      images ->
        # Convert images to processable paths/URLs
        processable_paths =
          Enum.map(images, fn image ->
            if Medpack.FileManager.use_s3_storage?() do
              Logger.info("Using S3 storage, generating presigned URL for: #{image.s3_key}")
              # For S3, get presigned URL for analysis
              url = Medpack.S3FileManager.get_presigned_url(image.s3_key)
              Logger.info("Generated presigned URL: #{url}")
              url
            else
              Logger.info("Using local storage, s3_key: #{image.s3_key}")
              # For local files, use centralized path resolution
              processable_path = Medpack.FileManager.resolve_file_path(image.s3_key)
              Logger.info("Converted to processable path: #{processable_path}")
              processable_path
            end
          end)
          # Remove any nil URLs
          |> Enum.reject(&is_nil/1)

        case processable_paths do
          [] ->
            Logger.error("Failed to generate any processable paths for #{length(images)} images")

            {:error, :failed_to_generate_presigned_url}

          [single_path] ->
            Logger.info("Starting ImageAnalyzer with single photo: #{single_path}")

            case ImageAnalyzer.analyze_medicine_photo(single_path) do
              {:ok, results} ->
                Logger.info("ImageAnalyzer completed successfully")
                {:ok, results}

              {:error, reason} ->
                Logger.error("ImageAnalyzer failed: #{inspect(reason)}")
                {:error, reason}
            end

          multiple_paths ->
            Logger.info("Starting ImageAnalyzer with #{length(multiple_paths)} photos")

            case ImageAnalyzer.analyze_medicine_photos(multiple_paths) do
              {:ok, results} ->
                Logger.info("Multi-photo ImageAnalyzer completed successfully")
                {:ok, results}

              {:error, reason} ->
                Logger.error("Multi-photo ImageAnalyzer failed: #{inspect(reason)}")
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
