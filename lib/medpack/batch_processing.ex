defmodule Medpack.BatchProcessing do
  @moduledoc """
  The BatchProcessing context for handling batch medicine operations.
  """

  import Ecto.Query, warn: false
  alias Medpack.Repo
  alias Medpack.BatchProcessing.Entry
  alias Medpack.BatchProcessing.EntryImage
  alias Medpack.Jobs.AnalyzeMedicinePhotoJob

  require Logger

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
  def get_entry(id), do: Repo.get(Entry, id)

  @doc """
  Gets a batch entry by ID, raising if not found.
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
  Returns an `%Ecto.Changeset{}` for tracking entry changes.
  """
  def change_entry(%Entry{} = entry, attrs \\ %{}) do
    Entry.changeset(entry, attrs)
  end

  @doc """
  Returns entries that are ready for analysis (have photos and pending analysis).
  """
  def list_ready_for_analysis() do
    # Get entry IDs that have images first
    entry_ids_with_images =
      EntryImage
      |> select([i], i.batch_entry_id)
      |> distinct(true)
      |> Repo.all()

    # Then get entries with those IDs that are pending analysis
    Entry
    |> where([e], e.id in ^entry_ids_with_images)
    |> where([e], e.ai_analysis_status == :pending)
    |> preload(:images)
    |> Repo.all()
  end

  @doc """
  Generates a new batch_id as a UUID string.
  """
  def generate_batch_id do
    Ecto.UUID.generate()
  end

  @doc """
  Creates multiple batch entries at once.
  """
  def create_batch_entries(count) when is_integer(count) and count > 0 do
    batch_id = generate_batch_id()

    entries =
      1..count
      |> Enum.map(fn number ->
        %{
          batch_id: batch_id,
          entry_number: number,
          status: :pending,
          ai_analysis_status: :pending,
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
  Saves a single batch entry as a medicine with photo handling.
  """
  def save_entry_as_medicine(entry) do
    Logger.info("Saving entry #{entry.id} as medicine with #{length(entry.images)} images")

    # First, copy photos to permanent medicine storage
    case copy_photos_for_medicine(entry.images, entry.id) do
      {:ok, photo_paths} ->
        Logger.info("Successfully copied #{length(photo_paths)} photos: #{inspect(photo_paths)}")

        # Merge AI results with photo paths, ensuring we override any existing photo paths
        default_photo_path = List.first(photo_paths)
        medicine_attrs =
          entry.ai_results
          |> Map.delete("photo_paths")
          |> Map.put("photo_paths", photo_paths)
          |> Map.put("default_photo_path", default_photo_path)

        Logger.info(
          "Creating medicine with photo_paths: #{inspect(medicine_attrs["photo_paths"])}"
        )

        case Medpack.Medicines.create_medicine(medicine_attrs) do
          {:ok, medicine} ->
            Logger.info("Successfully created medicine #{medicine.id}, cleaning up batch photos")
            # Clean up batch photos only after successful medicine creation
            cleanup_batch_photos(entry.images)
            # Mark entry as complete
            case update_entry(entry, %{status: :complete}) do
              {:ok, _updated_entry} ->
                Logger.info("Successfully marked entry #{entry.id} as complete")
                {:ok, medicine}

              {:error, changeset} ->
                Logger.error("Failed to mark entry as complete: #{inspect(changeset.errors)}")
                # Still return success for medicine creation, but log the error
                {:ok, medicine}
            end

          {:error, changeset} ->
            Logger.error("Failed to create medicine: #{inspect(changeset.errors)}")
            # If medicine creation failed, clean up the copied photos
            Enum.each(photo_paths, &Medpack.FileManager.delete_file/1)
            {:error, changeset}
        end

      {:error, reason} ->
        Logger.error("Failed to copy photos for entry #{entry.id}: #{reason}")
        # Return a properly formatted changeset-like error
        error_changeset = %{
          errors: [photo_paths: {"Failed to copy photos: #{reason}", []}],
          valid?: false
        }

        {:error, error_changeset}
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
    # Use the centralized path resolution utility
    source_path = Medpack.FileManager.resolve_file_path(image.s3_key)

    # Use the project's priv/static directory (not the compiled app directory)
    dest_path = Path.join(["priv", "static", "uploads", "medicines", new_filename])

    # Ensure the medicines directory exists
    dest_dir = Path.dirname(dest_path)
    File.mkdir_p!(dest_dir)

    Logger.info("Copying batch photo: #{image.s3_key} -> #{dest_path}")
    Logger.info("Resolved source path: #{source_path}")

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
  Updates an entry's AI analysis results and marks as complete.
  """
  def complete_entry_analysis(entry_id, ai_results) do
    case get_entry(entry_id) do
      nil ->
        {:error, :not_found}

      entry ->
        update_entry(entry, %{
          ai_analysis_status: :complete,
          ai_results: ai_results,
          analyzed_at: DateTime.utc_now()
        })
    end
  end

  @doc """
  Handles photo upload processing for an entry.
  """
  def handle_entry_photo_upload(entry_id, file_info_list) when is_list(file_info_list) do
    case get_entry(entry_id) do
      nil -> {:error, :entry_not_found}
      entry -> process_entry_photos(entry, file_info_list)
    end
  end

  @doc """
  Removes a specific photo from an entry by index.
  """
  def remove_entry_photo_by_index(entry_id, photo_index) do
    try do
      entry = get_entry_with_images!(entry_id)
      images = entry.images

      if photo_index >= 0 and photo_index < length(images) do
        image_to_remove = Enum.at(images, photo_index)

        # Delete the file
        Medpack.FileManager.delete_file(image_to_remove.s3_key)

        # Delete the database record
        delete_entry_image(image_to_remove)

        {:ok, :photo_removed}
      else
        {:error, :invalid_photo_index}
      end
    rescue
      Ecto.NoResultsError -> {:error, :entry_not_found}
    end
  end

  @doc """
  Schedules AI analysis for an entry with debounce logic.
  """
  def schedule_entry_analysis(entry_id, delay_seconds \\ 5) do
    # Send message to trigger analysis after delay
    # This will be handled by the LiveView process
    Process.send_after(self(), {:start_analysis_countdown, entry_id, delay_seconds}, 0)
    :ok
  end

  @doc """
  Gets photo display data for an entry.
  """
  def get_entry_photo_display_data(entry_id) do
    try do
      entry = get_entry_with_images!(entry_id)

      photo_data =
        entry.images
        |> Enum.sort_by(& &1.upload_order)
        |> Enum.map(fn image ->
          %{
            s3_key: image.s3_key,
            web_url: EntryImage.get_s3_url(image),
            filename: image.original_filename,
            size: image.file_size,
            human_size: EntryImage.human_file_size(image)
          }
        end)

      {:ok, photo_data}
    rescue
      Ecto.NoResultsError -> {:error, :entry_not_found}
    end
  end

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
        validation_errors: [],
        analysis_countdown: 0,
        analysis_timer_ref: nil
      }
    end)
  end

  @doc """
  Gets entries ready for analysis in a batch.
  """
  def get_batch_entries_ready_for_analysis() do
    Entry
    |> join(:inner, [e], i in assoc(e, :images))
    |> where([e], e.ai_analysis_status == :pending)
    |> distinct([e], e.id)
    |> preload(:images)
    |> Repo.all()
  end

  @doc """
  Lists all batch entries that are not fully processed (i.e., not complete/approved/rejected).
  Used to show in-progress batch entries on the /add page after reload.
  """
  def list_unprocessed_entries do
    Entry
    |> where([e], e.status != :complete)
    |> order_by([e], asc: e.inserted_at)
    |> preload(:images)
    |> Repo.all()
  end

  # Private helper functions

  defp process_entry_photos(entry, file_info_list) do
    try do
      # Create EntryImage records for each photo
      results =
        file_info_list
        |> Enum.with_index()
        |> Enum.map(fn {file_info, index} ->
          create_entry_image(%{
            batch_entry_id: entry.id,
            s3_key: file_info.path,
            original_filename: file_info.filename,
            file_size: file_info.size,
            content_type: get_content_type_from_filename(file_info.filename),
            upload_order: index
          })
        end)

      # Check if all images were created successfully
      if Enum.all?(results, &match?({:ok, _}, &1)) do
        {:ok, length(file_info_list)}
      else
        {:error, :failed_to_save_some_images}
      end
    rescue
      e -> {:error, "Failed to process photos: #{Exception.message(e)}"}
    end
  end

  defp get_content_type_from_filename(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      _ -> "image/jpeg"
    end
  end
end
