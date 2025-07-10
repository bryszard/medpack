defmodule MedpackWeb.BatchMedicineLive.EntryManager do
  @moduledoc """
  Manages batch entry manipulation and state management.

  This module handles entry creation, updates, and state transitions
  for the batch medicine LiveView.
  """

  @doc """
  Creates empty in-memory entry structs for the LiveView.
  """
  def create_empty_entries(count, start_number \\ 0) do
    (start_number + 1)..(start_number + count)
    |> Enum.map(fn i ->
      %{
        id: "entry_#{System.unique_integer([:positive])}",
        number: i,
        photos_uploaded: 0,
        photo_entries: [],
        photo_paths: [],
        photo_web_paths: [],
        ai_analysis_status: :pending,
        ai_results: %{},
        approval_status: :pending,
        validation_errors: [],
        analysis_countdown: 0,
        analysis_timer_ref: nil
      }
    end)
  end

  @doc """
  Normalizes entry IDs for comparison.
  """
  def normalize_entry_id(nil), do: nil
  def normalize_entry_id(entry_id) when is_integer(entry_id), do: entry_id

  def normalize_entry_id(entry_id) when is_binary(entry_id) do
    case Integer.parse(entry_id) do
      {id, _} -> id
      # Keep as string if it's not a valid integer
      :error -> entry_id
    end
  end

  def normalize_entry_id(entry_id), do: entry_id

  @doc """
  Replaces an entry in a list by ID.
  """
  def replace_entry(entries, updated_entry) do
    Enum.map(entries, fn entry ->
      if entry.id == updated_entry.id do
        updated_entry
      else
        entry
      end
    end)
  end

  @doc """
  Replaces an entry by original ID (handles cases where ID changes from string to integer).
  """
  def replace_entry_by_original_id(entries, original_id, updated_entry) do
    Enum.map(entries, fn entry ->
      if entry.id == original_id do
        updated_entry
      else
        entry
      end
    end)
  end

  @doc """
  Finds an entry by number.
  """
  def find_entry_by_number(entries, number) do
    Enum.find(entries, &(&1.number == number))
  end

  @doc """
  Finds an entry by upload config name.
  """
  def find_entry_by_upload_config(entries, upload_config_name) do
    # The upload_config_name is an atom like :entry_1_photos
    # Extract the entry number from it
    upload_config_str = Atom.to_string(upload_config_name)

    case Regex.run(~r/entry_(\d+)_photos/, upload_config_str) do
      [_, number_str] ->
        number = String.to_integer(number_str)
        find_entry_by_number(entries, number)

      _ ->
        nil
    end
  end

  @doc """
  Updates an entry's approval status.
  """
  def update_entry_approval_status(entries, entry_id, status) do
    normalized_id = normalize_entry_id(entry_id)

    Enum.map(entries, fn entry ->
      if normalize_entry_id(entry.id) == normalized_id do
        %{entry | approval_status: status}
      else
        entry
      end
    end)
  end

  @doc """
  Updates an entry's AI analysis status.
  """
  def update_entry_analysis_status(entries, entry_id, status, ai_results \\ nil) do
    normalized_id = normalize_entry_id(entry_id)

    Enum.map(entries, fn entry ->
      if normalize_entry_id(entry.id) == normalized_id do
        updated_entry = %{entry | ai_analysis_status: status}

        if ai_results do
          %{updated_entry | ai_results: ai_results}
        else
          updated_entry
        end
      else
        entry
      end
    end)
  end

  @doc """
  Removes an entry from the list by ID.
  """
  def remove_entry(entries, entry_id) do
    normalized_id = normalize_entry_id(entry_id)
    Enum.reject(entries, &(normalize_entry_id(&1.id) == normalized_id))
  end

  @doc """
  Updates entry photo information after upload.
  """
  def update_entry_photos(entries, entry_id, photo_paths, photo_web_paths, photo_entries) do
    normalized_id = normalize_entry_id(entry_id)

    Enum.map(entries, fn entry ->
      if normalize_entry_id(entry.id) == normalized_id do
        %{
          entry
          | photos_uploaded: length(photo_paths),
            photo_paths: photo_paths,
            photo_web_paths: photo_web_paths,
            photo_entries: photo_entries
        }
      else
        entry
      end
    end)
  end

  @doc """
  Removes a photo from an entry by index.
  """
  def remove_entry_photo(entries, entry_id, photo_index) do
    normalized_id = normalize_entry_id(entry_id)

    Enum.map(entries, fn entry ->
      if normalize_entry_id(entry.id) == normalized_id do
        # Remove the photo at the specified index from all photo arrays
        updated_photo_paths = List.delete_at(entry.photo_paths, photo_index)
        updated_photo_web_paths = List.delete_at(entry.photo_web_paths, photo_index)
        updated_photo_entries = List.delete_at(entry.photo_entries, photo_index)

        %{
          entry
          | photos_uploaded: max(0, entry.photos_uploaded - 1),
            photo_paths: updated_photo_paths,
            photo_web_paths: updated_photo_web_paths,
            photo_entries: updated_photo_entries,
            ai_analysis_status:
              if(updated_photo_paths == [], do: :pending, else: entry.ai_analysis_status),
            ai_results: if(updated_photo_paths == [], do: %{}, else: entry.ai_results),
            analysis_countdown: 0,
            analysis_timer_ref: nil
        }
      else
        entry
      end
    end)
  end

  @doc """
  Removes all photos from an entry.
  """
  def remove_all_entry_photos(entries, entry_id) do
    normalized_id = normalize_entry_id(entry_id)

    Enum.map(entries, fn entry ->
      if normalize_entry_id(entry.id) == normalized_id do
        %{
          entry
          | photos_uploaded: 0,
            photo_paths: [],
            photo_web_paths: [],
            photo_entries: [],
            ai_analysis_status: :pending,
            ai_results: %{},
            analysis_countdown: 0,
            analysis_timer_ref: nil
        }
      else
        entry
      end
    end)
  end

  @doc """
  Updates entry countdown timer state.
  """
  def update_entry_countdown(entries, entry_id, countdown, timer_ref \\ nil) do
    normalized_id = normalize_entry_id(entry_id)

    Enum.map(entries, fn entry ->
      if normalize_entry_id(entry.id) == normalized_id do
        %{entry | analysis_countdown: countdown, analysis_timer_ref: timer_ref}
      else
        entry
      end
    end)
  end

  @doc """
  Cancels countdown timer for an entry.
  """
  def cancel_entry_timer(entries, entry_id) do
    normalized_id = normalize_entry_id(entry_id)

    Enum.map(entries, fn entry ->
      if normalize_entry_id(entry.id) == normalized_id do
        # Cancel existing timer if any
        if entry.analysis_timer_ref do
          Process.cancel_timer(entry.analysis_timer_ref)
        end

        %{entry | analysis_timer_ref: nil, analysis_countdown: 0}
      else
        entry
      end
    end)
  end

  @doc """
  Updates entry with edited medicine data.
  """
  def update_entry_medicine_data(entries, entry_id, medicine_params) do
    normalized_id = normalize_entry_id(entry_id)

    Enum.map(entries, fn entry ->
      if normalize_entry_id(entry.id) == normalized_id do
        %{entry | ai_results: medicine_params, approval_status: :approved}
      else
        entry
      end
    end)
  end

  @doc """
  Gets entries that are ready for batch analysis.
  """
  def get_entries_ready_for_analysis(entries) do
    entries
    |> Enum.filter(fn entry ->
      entry.photos_uploaded > 0 and entry.ai_analysis_status == :pending
    end)
  end

  @doc """
  Gets approved entries ready for saving.
  """
  def get_approved_entries(entries) do
    Enum.filter(entries, &(&1.approval_status == :approved))
  end

  @doc """
  Gets rejected entries.
  """
  def get_rejected_entries(entries) do
    Enum.filter(entries, &(&1.approval_status == :rejected))
  end

  @doc """
  Gets entries with complete analysis pending review.
  """
  def get_entries_pending_review(entries) do
    Enum.filter(entries, &(&1.ai_analysis_status == :complete and &1.approval_status == :pending))
  end

  @doc """
  Approves all completed entries.
  """
  def approve_all_complete_entries(entries) do
    Enum.map(entries, fn entry ->
      if entry.ai_analysis_status == :complete and entry.approval_status == :pending do
        %{entry | approval_status: :approved}
      else
        entry
      end
    end)
  end

  @doc """
  Removes all rejected entries.
  """
  def clear_rejected_entries(entries) do
    Enum.reject(entries, &(&1.approval_status == :rejected))
  end

  @doc """
  Validates if an entry can be saved.
  """
  def can_save_entry?(entry) do
    entry.approval_status == :approved and
      entry.ai_analysis_status == :complete and
      not is_nil(entry.ai_results) and
      map_size(entry.ai_results) > 0
  end

  @doc """
  Gets batch statistics from entries.
  """
  def get_batch_stats(entries) do
    total = length(entries)
    with_photos = Enum.count(entries, &(&1.photos_uploaded > 0))
    processing = Enum.count(entries, &(&1.ai_analysis_status == :processing))
    complete = Enum.count(entries, &(&1.ai_analysis_status == :complete))
    failed = Enum.count(entries, &(&1.ai_analysis_status == :failed))
    approved = Enum.count(entries, &(&1.approval_status == :approved))
    rejected = Enum.count(entries, &(&1.approval_status == :rejected))

    pending_review =
      Enum.count(
        entries,
        &(&1.ai_analysis_status == :complete and &1.approval_status == :pending)
      )

    %{
      total: total,
      with_photos: with_photos,
      processing: processing,
      complete: complete,
      failed: failed,
      approved: approved,
      rejected: rejected,
      pending_review: pending_review
    }
  end
end
