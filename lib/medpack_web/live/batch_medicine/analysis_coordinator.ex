defmodule MedpackWeb.BatchMedicineLive.AnalysisCoordinator do
  @moduledoc """
  Coordinates AI analysis for batch medicine entries.

  This module handles analysis scheduling, progress tracking, and result processing
  for the batch medicine LiveView.
  """

  require Logger

  alias Medpack.AI.ImageAnalyzer
  alias MedpackWeb.BatchMedicineLive.EntryManager

  @doc """
  Starts analysis debounce timer for an entry.
  """
  def start_analysis_debounce(entry_id, delay_seconds \\ 5) do
    # Cancel any existing timer for this entry
    send(self(), {:cancel_analysis_timer, entry_id})

    # Start countdown
    send(self(), {:start_analysis_countdown, entry_id, delay_seconds})
  end

  @doc """
  Handles analysis countdown tick.
  """
  def handle_analysis_countdown(entries, entry_id, seconds) do
    updated_entries = EntryManager.update_entry_countdown(entries, entry_id, seconds)

    if seconds > 0 do
      # Schedule next tick
      timer_ref = Process.send_after(self(), {:countdown_tick, entry_id, seconds - 1}, 1000)
      EntryManager.update_entry_countdown(updated_entries, entry_id, seconds, timer_ref)
    else
      # Time's up, start analysis
      trigger_entry_analysis(updated_entries, entry_id)
    end
  end

  @doc """
  Cancels analysis timer for an entry.
  """
  def cancel_analysis_timer(entries, entry_id) do
    EntryManager.cancel_entry_timer(entries, entry_id)
  end

  @doc """
  Triggers immediate analysis for an entry.
  """
  def trigger_entry_analysis(entries, entry_id) do
    # Always use entry.id (UUID) for DB lookups
    entry = Enum.find(entries, &(&1.id == entry_id))

    if entry && entry.photos_uploaded > 0 do
      case safe_get_database_entry(entry.id) do
        {:ok, db_entry} ->
          submit_database_entry_for_analysis(entries, db_entry)

        {:error, _} ->
          entries_processing =
            EntryManager.update_entry_analysis_status(entries, entry_id, :processing)

          process_in_memory_entry_analysis(entries_processing, entry)
      end
    else
      {entries, nil}
    end
  end

  @doc """
  Processes batch analysis for multiple entries.
  """
  def analyze_batch_entries(entries) do
    entries_with_photos = EntryManager.get_entries_ready_for_analysis(entries)

    if entries_with_photos == [] do
      {:error, "No entries with photos to analyze"}
    else
      # Start async analysis
      analysis_results = analyze_multiple_entries(entries_with_photos)
      {:ok, analysis_results}
    end
  end

  @doc """
  Applies analysis results to entries.
  """
  def apply_analysis_results(entries, analysis_results) do
    analysis_map = Map.new(analysis_results)

    Enum.map(entries, fn entry ->
      case Map.get(analysis_map, entry.id) do
        nil ->
          entry

        :failed ->
          %{entry | ai_analysis_status: :failed}

        ai_results ->
          %{entry | ai_analysis_status: :complete, ai_results: ai_results}
      end
    end)
  end

  @doc """
  Handles analysis updates from Oban jobs.
  """
  def handle_analysis_update(entries, %{entry_id: entry_id, status: status, data: data}) do
    case status do
      :complete ->
        EntryManager.update_entry_analysis_status(entries, entry_id, :complete, data)

      :failed ->
        entries = EntryManager.update_entry_analysis_status(entries, entry_id, :failed)
        # Add error message to validation_errors
        add_error_to_entry(entries, entry_id, data.error || "Analysis failed")

      :processing ->
        EntryManager.update_entry_analysis_status(entries, entry_id, :processing)

      _ ->
        entries
    end
  end

  @doc """
  Retries analysis for a failed entry.
  """
  def retry_entry_analysis(entries, entry_id) do
    # Reset status to pending and trigger analysis
    updated_entries = EntryManager.update_entry_analysis_status(entries, entry_id, :pending)
    trigger_entry_analysis(updated_entries, entry_id)
  end

  @doc """
  Gets analysis progress for a batch.
  """
  def get_analysis_progress(entries) do
    total_with_photos = Enum.count(entries, &(&1.photos_uploaded > 0))

    if total_with_photos == 0 do
      0
    else
      completed = Enum.count(entries, &(&1.ai_analysis_status in [:complete, :failed]))
      round(completed / total_with_photos * 100)
    end
  end

  # Private functions

  defp submit_database_entry_for_analysis(entries, db_entry) do
    Logger.info("Found database entry #{db_entry.id}, submitting analysis job")

    case Medpack.BatchProcessing.submit_for_analysis(db_entry) do
      {:ok, _updated_entry} ->
        Logger.info("Analysis job submitted successfully")

        # Update the UI to show processing status
        updated_entries =
          EntryManager.update_entry_analysis_status(entries, db_entry.id, :processing)

        flash_message = "Analysis started for entry..."

        {updated_entries, {:info, flash_message}}

      {:error, reason} ->
        Logger.error("Failed to submit analysis job: #{inspect(reason)}")
        flash_message = "Failed to start analysis"

        {entries, {:error, flash_message}}
    end
  end

  defp process_in_memory_entry_analysis(entries, entry) do
    Logger.info("Processing in-memory entry analysis for #{entry.id}")

    case analyze_entry_photos(entry) do
      {:ok, ai_results} ->
        updated_entry = %{
          entry
          | ai_analysis_status: :complete,
            ai_results: ai_results,
            analysis_countdown: 0,
            analysis_timer_ref: nil
        }

        updated_entries = EntryManager.replace_entry(entries, updated_entry)
        flash_message = "Analysis complete for entry! Review the extracted data."

        {updated_entries, {:info, flash_message}}

      {:error, reason} ->
        updated_entry = %{
          entry
          | ai_analysis_status: :failed,
            validation_errors: ["AI analysis failed: #{inspect(reason)}"],
            analysis_countdown: 0,
            analysis_timer_ref: nil
        }

        updated_entries = EntryManager.replace_entry(entries, updated_entry)
        flash_message = "Analysis failed for entry: #{inspect(reason)}"

        {updated_entries, {:error, flash_message}}
    end
  end

  defp analyze_entry_photos(entry) do
    case entry.photo_paths do
      [] ->
        {:error, "No photos to analyze"}

      [single_path] ->
        # Convert path to proper format for AI analysis
        processable_path = get_processable_path(single_path)
        ImageAnalyzer.analyze_medicine_photo(processable_path)

      multiple_paths ->
        # Convert paths to proper format for AI analysis
        processable_paths =
          multiple_paths
          |> Enum.map(&get_processable_path/1)
          |> Enum.reject(&is_nil/1)

        case processable_paths do
          [] ->
            {:error, "No valid photo paths found"}

          paths ->
            ImageAnalyzer.analyze_medicine_photos(paths)
        end
    end
  end

  defp get_processable_path(photo_path) do
    if Medpack.FileManager.use_s3_storage?() do
      # For S3, get presigned URL for analysis
      if String.starts_with?(photo_path, "http") do
        photo_path
      else
        Medpack.S3FileManager.get_presigned_url(photo_path)
      end
    else
      # For local files, use centralized path resolution
      Medpack.FileManager.resolve_file_path(photo_path)
    end
  end

  defp analyze_multiple_entries(entries) do
    entries
    |> Enum.map(fn entry ->
      ai_results =
        case analyze_entry_photos(entry) do
          {:ok, results} -> results
          {:error, _} -> :failed
        end

      {entry.id, ai_results}
    end)
  end

  defp safe_get_database_entry(entry_id) when is_binary(entry_id) do
    if String.length(entry_id) == 36 and String.contains?(entry_id, "-") do
      try do
        {:ok, Medpack.BatchProcessing.get_entry!(entry_id)}
      rescue
        Ecto.NoResultsError -> {:error, :not_found}
      end
    else
      {:error, :invalid_id}
    end
  end

  defp safe_get_database_entry(_entry_id) do
    {:error, :invalid_id}
  end

  defp add_error_to_entry(entries, entry_id, error_message) do
    normalized_id = EntryManager.normalize_entry_id(entry_id)

    Enum.map(entries, fn entry ->
      if EntryManager.normalize_entry_id(entry.id) == normalized_id do
        current_errors = entry.validation_errors || []
        %{entry | validation_errors: [error_message | current_errors]}
      else
        entry
      end
    end)
  end
end
