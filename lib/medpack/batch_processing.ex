defmodule Medpack.BatchProcessing do
  @moduledoc """
  The BatchProcessing context for handling batch medicine operations.
  """

  import Ecto.Query, warn: false
  alias Medpack.Repo
  alias Medpack.BatchProcessing.Entry
  alias Medpack.Jobs.AnalyzeMedicinePhotoJob

  @doc """
  Creates a new batch processing entry.
  """
  def create_entry(attrs \\ %{}) do
    %Entry{}
    |> Entry.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a batch entry by ID.
  """
  def get_entry!(id), do: Repo.get!(Entry, id)

  @doc """
  Lists all batch entries for a given batch ID.
  """
  def list_entries_by_batch(batch_id) do
    Entry
    |> where([e], e.batch_id == ^batch_id)
    |> order_by([e], e.entry_number)
    |> Repo.all()
  end

  @doc """
  Updates a batch entry.
  """
  def update_entry(%Entry{} = entry, attrs) do
    entry
    |> Entry.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a batch entry.
  """
  def delete_entry(%Entry{} = entry) do
    Repo.delete(entry)
  end

  @doc """
  Creates multiple batch entries at once.
  """
  def create_batch_entries(count, batch_id \\ nil) when is_integer(count) and count > 0 do
    batch_id = batch_id || generate_batch_id()

    entries =
      1..count
      |> Enum.map(fn number ->
        %{
          batch_id: batch_id,
          entry_number: number,
          status: :pending,
          ai_analysis_status: :pending,
          approval_status: :pending,
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
          updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        }
      end)

    case Repo.insert_all(Entry, entries, returning: true) do
      {^count, entries} -> {:ok, entries}
      _ -> {:error, :batch_creation_failed}
    end
  end

  @doc """
  Submits a batch entry for AI analysis.
  """
  def submit_for_analysis(%Entry{} = entry) do
    with {:ok, updated_entry} <- update_entry(entry, %{ai_analysis_status: :processing}) do
      # Enqueue the analysis job
      %{entry_id: updated_entry.id}
      |> AnalyzeMedicinePhotoJob.new(queue: :ai_analysis)
      |> Oban.insert()

      {:ok, updated_entry}
    end
  end

  @doc """
  Submits multiple batch entries for AI analysis.
  """
  def submit_batch_for_analysis(entries) when is_list(entries) do
    results =
      Enum.map(entries, fn entry ->
        case submit_for_analysis(entry) do
          {:ok, updated_entry} -> {:ok, updated_entry}
          {:error, reason} -> {:error, entry.id, reason}
        end
      end)

    successes = Enum.count(results, &match?({:ok, _}, &1))
    failures = Enum.count(results, &match?({:error, _, _}, &1))

    {:ok, %{successes: successes, failures: failures, results: results}}
  end

  @doc """
  Updates the AI analysis results for an entry.
  """
  def update_analysis_results(%Entry{} = entry, ai_results) do
    update_entry(entry, %{
      ai_analysis_status: :complete,
      ai_results: ai_results,
      analyzed_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks an entry analysis as failed.
  """
  def mark_analysis_failed(%Entry{} = entry, error_message \\ nil) do
    update_entry(entry, %{
      ai_analysis_status: :failed,
      error_message: error_message,
      analyzed_at: DateTime.utc_now()
    })
  end

  @doc """
  Approves a batch entry.
  """
  def approve_entry(%Entry{} = entry) do
    update_entry(entry, %{approval_status: :approved})
  end

  @doc """
  Rejects a batch entry.
  """
  def reject_entry(%Entry{} = entry) do
    update_entry(entry, %{approval_status: :rejected})
  end

  @doc """
  Gets entries that are ready for saving (approved and have analysis results).
  """
  def get_saveable_entries(batch_id) do
    Entry
    |> where([e], e.batch_id == ^batch_id)
    |> where([e], e.approval_status == :approved)
    |> where([e], e.ai_analysis_status == :complete)
    |> where([e], not is_nil(e.ai_results))
    |> Repo.all()
  end

  @doc """
  Gets summary statistics for a batch.
  """
  def get_batch_summary(batch_id) do
    query = from e in Entry, where: e.batch_id == ^batch_id

    total = Repo.aggregate(query, :count)

    pending =
      query
      |> where([e], e.ai_analysis_status == :pending)
      |> Repo.aggregate(:count)

    processing =
      query
      |> where([e], e.ai_analysis_status == :processing)
      |> Repo.aggregate(:count)

    complete =
      query
      |> where([e], e.ai_analysis_status == :complete)
      |> Repo.aggregate(:count)

    failed =
      query
      |> where([e], e.ai_analysis_status == :failed)
      |> Repo.aggregate(:count)

    approved =
      query
      |> where([e], e.approval_status == :approved)
      |> Repo.aggregate(:count)

    rejected =
      query
      |> where([e], e.approval_status == :rejected)
      |> Repo.aggregate(:count)

    %{
      total: total,
      pending: pending,
      processing: processing,
      complete: complete,
      failed: failed,
      approved: approved,
      rejected: rejected
    }
  end

  @doc """
  Saves approved batch entries as medicines in the main inventory.
  """
  def save_approved_medicines(batch_id) do
    approved_entries = get_saveable_entries(batch_id)

    if approved_entries == [] do
      {:ok, %{saved: 0, failed: 0, results: []}}
    else
      results =
        Enum.map(approved_entries, fn entry ->
          case Medpack.Medicines.create_medicine(entry.ai_results) do
            {:ok, medicine} ->
              # Clean up the photo file after successful save
              if entry.photo_path do
                Medpack.FileManager.delete_file(entry.photo_path)
              end

              {:ok, medicine}

            {:error, changeset} ->
              {:error, entry.id, changeset}
          end
        end)

      saved = Enum.count(results, &match?({:ok, _}, &1))
      failed = Enum.count(results, &match?({:error, _, _}, &1))

      # Remove successfully saved entries
      if saved > 0 do
        successful_entry_ids = get_successful_entry_ids(results, approved_entries)

        Enum.each(successful_entry_ids, fn entry_id ->
          case get_entry!(entry_id) do
            nil -> :ok
            entry -> delete_entry(entry)
          end
        end)
      end

      {:ok, %{saved: saved, failed: failed, results: results}}
    end
  end

  @doc """
  Gets entries with uploaded photos that are ready for analysis.
  """
  def get_entries_ready_for_analysis(batch_id) do
    Entry
    |> where([e], e.batch_id == ^batch_id)
    |> where([e], not is_nil(e.photo_path))
    |> where([e], e.ai_analysis_status == :pending)
    |> Repo.all()
  end

  # Private functions

  defp get_successful_entry_ids(results, entries) do
    results
    |> Enum.with_index()
    |> Enum.filter(&match?({{:ok, _}, _}, &1))
    |> Enum.map(fn {{:ok, _}, index} ->
      Enum.at(entries, index).id
    end)
  end

  defp generate_batch_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end
end
