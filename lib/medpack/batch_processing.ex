defmodule Medpack.BatchProcessing do
  @moduledoc """
  The BatchProcessing context for handling batch medicine operations.
  """

  import Ecto.Query, warn: false
  alias Medpack.Repo
  alias Medpack.BatchProcessing.Entry
  alias Medpack.BatchProcessing.EntryImage
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
  Gets a batch entry by ID with preloaded images.
  """
  def get_entry_with_images!(id) do
    Entry
    |> where([e], e.id == ^id)
    |> preload(:images)
    |> Repo.one!()
  end

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
  Lists all batch entries for a given batch ID with preloaded images.
  """
  def list_entries_by_batch_with_images(batch_id) do
    Entry
    |> where([e], e.batch_id == ^batch_id)
    |> order_by([e], e.entry_number)
    |> preload(:images)
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
  Creates an image for a batch entry.
  """
  def create_entry_image(attrs \\ %{}) do
    %EntryImage{}
    |> EntryImage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets all images for a batch entry.
  """
  def list_entry_images(entry_id) do
    EntryImage
    |> where([i], i.batch_entry_id == ^entry_id)
    |> order_by([i], i.upload_order)
    |> Repo.all()
  end

  @doc """
  Deletes an entry image.
  """
  def delete_entry_image(%EntryImage{} = image) do
    Repo.delete(image)
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
      # Preload images for all entries
      entries_with_images =
        Enum.map(approved_entries, fn entry ->
          get_entry_with_images!(entry.id)
        end)

      results =
        Enum.map(entries_with_images, fn entry ->
          case save_entry_as_medicine(entry) do
            {:ok, medicine} -> {:ok, medicine}
            {:error, changeset} -> {:error, entry.id, changeset}
          end
        end)

      saved = Enum.count(results, &match?({:ok, _}, &1))
      failed = Enum.count(results, &match?({:error, _, _}, &1))

      # Remove successfully saved entries
      if saved > 0 do
        successful_entry_ids = get_successful_entry_ids(results, entries_with_images)

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
  Saves a single batch entry as a medicine with photo handling.
  """
  def save_entry_as_medicine(entry) do
    require Logger
    Logger.info("Saving entry #{entry.id} as medicine with #{length(entry.images)} images")

    # First, copy photos to permanent medicine storage
    case copy_photos_for_medicine(entry.images, entry.id) do
      {:ok, photo_paths} ->
        Logger.info("Successfully copied #{length(photo_paths)} photos: #{inspect(photo_paths)}")

        # Merge AI results with photo paths, ensuring we override any existing photo paths
        medicine_attrs =
          entry.ai_results
          # Remove any existing photo paths from AI results
          |> Map.delete("photo_paths")
          |> Map.put("photo_paths", photo_paths)

        Logger.info(
          "Creating medicine with photo_paths: #{inspect(medicine_attrs["photo_paths"])}"
        )

        case Medpack.Medicines.create_medicine(medicine_attrs) do
          {:ok, medicine} ->
            Logger.info("Successfully created medicine #{medicine.id}, cleaning up batch photos")
            # Clean up batch photos only after successful medicine creation
            cleanup_batch_photos(entry.images)
            {:ok, medicine}

          {:error, changeset} ->
            Logger.error("Failed to create medicine: #{inspect(changeset.errors)}")
            # If medicine creation failed, clean up the copied photos
            Enum.each(photo_paths, &Medpack.FileManager.delete_file/1)
            {:error, changeset}
        end

      {:error, reason} ->
        Logger.error("Failed to copy photos for entry #{entry.id}: #{reason}")
        {:error, "Failed to copy photos: #{reason}"}
    end
  end

  # Copy photos from batch storage to permanent medicine storage
  defp copy_photos_for_medicine(images, entry_id) do
    results =
      images
      |> Enum.with_index()
      |> Enum.map(fn {image, index} ->
        copy_single_photo_for_medicine(image, entry_id, index)
      end)

    # Check if all copies were successful
    case Enum.all?(results, &match?({:ok, _}, &1)) do
      true ->
        photo_paths = Enum.map(results, fn {:ok, path} -> path end)
        {:ok, photo_paths}

      false ->
        # Clean up any successful copies
        results
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.each(fn {:ok, path} -> Medpack.FileManager.delete_file(path) end)

        {:error, "Failed to copy one or more photos"}
    end
  end

  # Copy a single photo to permanent medicine storage
  defp copy_single_photo_for_medicine(image, entry_id, index) do
    # Generate a new unique filename for the medicine photo
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    extension = Path.extname(image.original_filename)
    new_filename = "medicine_#{entry_id}_#{timestamp}_#{index}#{extension}"

    if Medpack.FileManager.use_s3_storage?() do
      # For S3: copy from batch location to medicine location
      copy_s3_photo_for_medicine(image, new_filename)
    else
      # For local storage: copy from batch location to medicine location
      copy_local_photo_for_medicine(image, new_filename)
    end
  end

  # Copy S3 photo to medicine storage
  defp copy_s3_photo_for_medicine(image, new_filename) do
    # For S3, we'll copy the object to a new key in medicine storage
    source_key = image.s3_key
    dest_key = "medicines/#{new_filename}"

    case Medpack.S3FileManager.copy_object(source_key, dest_key) do
      {:ok, _} -> {:ok, dest_key}
      {:error, reason} -> {:error, reason}
    end
  end

  # Copy local photo to medicine storage
  defp copy_local_photo_for_medicine(image, new_filename) do
    require Logger

    # For local storage, s3_key contains the full path
    source_path = image.s3_key

    # Use the project's priv/static directory (not the compiled app directory)
    dest_path = Path.join(["priv", "static", "uploads", "medicines", new_filename])

    # Ensure the medicines directory exists
    dest_dir = Path.dirname(dest_path)
    File.mkdir_p!(dest_dir)

    Logger.info("Copying batch photo: #{source_path} -> #{dest_path}")

    # Check if source file exists before copying
    if File.exists?(source_path) do
      case File.cp(source_path, dest_path) do
        :ok ->
          # Return the web path for the medicine photo
          web_path = "/uploads/medicines/#{new_filename}"
          Logger.info("Successfully copied photo, returning web path: #{web_path}")
          {:ok, web_path}

        {:error, reason} ->
          Logger.error("Failed to copy #{source_path} to #{dest_path}: #{reason}")
          {:error, "Failed to copy #{source_path} to #{dest_path}: #{reason}"}
      end
    else
      Logger.error("Source file does not exist: #{source_path}")
      {:error, "Source file does not exist: #{source_path}"}
    end
  end

  # Clean up batch photos after successful medicine creation
  defp cleanup_batch_photos(images) do
    Enum.each(images, fn image ->
      Medpack.FileManager.delete_file(image.s3_key)
      delete_entry_image(image)
    end)
  end

  @doc """
  Gets entries with uploaded photos that are ready for analysis.
  """
  def get_entries_ready_for_analysis(batch_id) do
    # Get entries that have at least one image and are pending analysis
    Entry
    |> join(:inner, [e], i in assoc(e, :images))
    |> where([e], e.batch_id == ^batch_id)
    |> where([e], e.ai_analysis_status == :pending)
    |> distinct([e], e.id)
    |> preload(:images)
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
