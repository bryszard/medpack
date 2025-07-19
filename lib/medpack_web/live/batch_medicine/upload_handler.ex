defmodule MedpackWeb.BatchMedicineLive.UploadHandler do
  require Logger
  alias MedpackWeb.BatchMedicineLive.EntryManager

  @moduledoc """
  Handles file upload logic for batch medicine entries.

  This module extracts upload-related functionality from the main LiveView
  to improve code organization and testability.
  """

    @doc """
  Configures upload settings for multiple entries.
  """
    def configure_uploads_for_entries(socket, entries) do
    Logger.info("Configuring uploads for #{length(entries)} entries")

    # First cancel any existing uploads to avoid duplicates
    socket_cleaned = clear_existing_uploads(socket)

    entries
    |> Enum.reduce(socket_cleaned, fn entry, acc_socket ->
      upload_key = String.to_atom("entry_#{entry.id}_photos")

      # Check if this upload already exists and has active entries
      case Map.get(acc_socket.assigns, :uploads, %{}) |> Map.get(upload_key) do
        nil ->
          # Upload doesn't exist, safe to allow
          Phoenix.LiveView.allow_upload(acc_socket, upload_key,
            accept: ~w(.jpg .jpeg .png),
            max_entries: 3,
            max_file_size: 10_000_000,
            auto_upload: true,
            progress: &handle_progress/3
          )

        upload_config ->
          # Upload exists, check if it has active entries
          case upload_config.entries do
            [] ->
              # No active entries, safe to allow (this will replace the existing config)
              Phoenix.LiveView.allow_upload(acc_socket, upload_key,
                accept: ~w(.jpg .jpeg .png),
                max_entries: 3,
                max_file_size: 10_000_000,
                auto_upload: true,
                progress: &handle_progress/3
              )

            active_entries ->
              # There are active entries, log warning and skip this upload
              Logger.warning("Skipping upload configuration for #{upload_key} - has #{length(active_entries)} active entries")
              acc_socket
          end
      end
    end)
  end

    # Clears existing upload configurations to prevent duplicates.
  defp clear_existing_uploads(socket) do
    # Check if uploads exist in socket assigns
    case Map.get(socket.assigns, :uploads) do
      nil ->
        # No uploads configured yet, return socket as-is
        socket

      existing_uploads when is_map(existing_uploads) ->
        # Get all entry upload keys that might exist
        entry_upload_keys =
          existing_uploads
          |> Map.keys()
          |> Enum.filter(fn key ->
            key |> Atom.to_string() |> String.match?(~r/^entry_\w+_photos$/)
          end)

        # Handle each existing entry upload to completely remove the configuration
        Enum.reduce(entry_upload_keys, socket, fn upload_key, acc_socket ->
          if Map.has_key?(acc_socket.assigns.uploads, upload_key) do
            upload_config = Map.get(acc_socket.assigns.uploads, upload_key)

            # Check if there are active entries in this upload
            case upload_config.entries do
              [] ->
                # No active entries, safe to disallow
                Phoenix.LiveView.disallow_upload(acc_socket, upload_key)

              active_entries ->
                # There are active entries, we need to handle them properly
                Logger.warning("Found #{length(active_entries)} active upload entries for #{upload_key}, consuming them")

                # Consume all active entries first, then disallow
                acc_socket
                |> consume_active_entries(upload_key, active_entries)
                |> Phoenix.LiveView.disallow_upload(upload_key)
            end
          else
            acc_socket
          end
        end)

      _ ->
        # Invalid uploads value, return socket as-is
        Logger.warning("Invalid uploads value in socket assigns: #{inspect(Map.get(socket.assigns, :uploads))}")
        socket
    end
  end

  @doc """
  Handles upload progress and triggers file processing when complete.
  """
  def handle_progress(upload_config_name, upload_entry, socket) do
    # When upload is complete (progress == 100), check if all uploads for this entry are done
    if upload_entry.done? do
      Logger.info("Upload complete for config: #{upload_config_name}")

      # Find the entry that matches this upload config
      entry = find_entry_by_upload_config(socket.assigns.entries, upload_config_name)

      if entry do
        # Check if all uploads for this entry are complete
        upload_config = Map.get(socket.assigns, :uploads, %{}) |> Map.get(upload_config_name)
        all_done? = Enum.all?(upload_config.entries, & &1.done?)

        if all_done? do
          Logger.info("All uploads complete for entry #{entry.id}, processing files...")
          send(self(), {:process_all_uploaded_files, entry, upload_config_name})
        else
          Logger.info("Waiting for other uploads to complete for entry #{entry.id}")
        end
      else
        Logger.warning("Could not find entry for upload config: #{upload_config_name}")
      end
    end

    {:noreply, socket}
  end

  @doc """
  Processes all uploaded files for an entry.
  """
  def process_uploaded_files(socket, entry, upload_config_name) do
    Logger.info("Processing all uploaded files for entry #{entry.id}")

    # Consume all uploaded files for this entry
    file_results =
      Phoenix.LiveView.consume_uploaded_entries(socket, upload_config_name, fn meta,
                                                                               upload_entry ->
        Logger.info("Processing file: #{upload_entry.client_name} for entry #{entry.id}")

        # Use FileManager to handle auto-uploaded files (local or S3)
        case Medpack.FileManager.save_auto_uploaded_file(meta, upload_entry, entry.id) do
          {:ok, result} when is_binary(result) ->
            # Local storage - result is file path
            Logger.info("File saved locally: #{result}")

            # Use FileManager to generate proper web URL
            web_path = Medpack.FileManager.get_photo_url(result)

            {:ok,
             %{
               path: result,
               web_path: web_path,
               filename: upload_entry.client_name,
               size: upload_entry.client_size
             }}

          {:ok, %{s3_key: s3_key, url: url}} ->
            # S3 storage - use URL for both path and web_path
            Logger.info("File saved to S3: #{s3_key}")

            {:ok,
             %{
               # Store S3 key as path for deletion later
               path: s3_key,
               # Use full URL for display
               web_path: url,
               filename: upload_entry.client_name,
               # Get size from upload entry
               size: upload_entry.client_size
             }}

          {:error, reason} ->
            Logger.error(
              "Failed to save file #{upload_entry.client_name} for entry #{entry.id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
      end)

    case file_results do
      file_info_list when is_list(file_info_list) and length(file_info_list) > 0 ->
        handle_successful_uploads(socket, entry, file_info_list)

      [] ->
        Logger.warning("No files to consume for entry #{entry.id}")
        {socket.assigns.entries, nil}
    end
  end

  @doc """
  Gets upload key for an entry.
  """
  def get_upload_key_for_entry(entry) do
    String.to_atom("entry_#{entry.id}_photos")
  end

    @doc """
  Safely configures uploads for entries with retry logic for parallel processing.
  """
  def safe_configure_uploads_for_entries(socket, entries, max_retries \\ 3) do
    Logger.info("Safely configuring uploads for #{length(entries)} entries with #{max_retries} max retries")

    # First check if there are active uploads and wait for them to complete
    socket_with_completed_uploads = wait_for_uploads_to_complete(socket, 2000)

    case configure_uploads_for_entries_with_retry(socket_with_completed_uploads, entries, max_retries) do
      {:ok, socket_with_uploads} ->
        Logger.info("Successfully configured uploads for #{length(entries)} entries")
        socket_with_uploads

      {:error, reason} ->
        Logger.error("Failed to configure uploads after #{max_retries} retries: #{inspect(reason)}")
        # Return the original socket to prevent crashes
        socket
    end
  end

  defp configure_uploads_for_entries_with_retry(socket, entries, retries_left) do
    try do
      socket_with_uploads = configure_uploads_for_entries(socket, entries)
      {:ok, socket_with_uploads}
    rescue
      error in ArgumentError ->
        if String.contains?(error.message, "cannot allow_upload on an existing upload with active entries") and retries_left > 0 do
          Logger.warning("Upload configuration failed due to active entries, retrying... (#{retries_left} retries left)")
          # Wait a bit before retrying to allow uploads to complete
          Process.sleep(100)
          configure_uploads_for_entries_with_retry(socket, entries, retries_left - 1)
        else
          {:error, error}
        end

      error ->
        {:error, error}
    end
  end

    @doc """
  Checks if any uploads have active entries that need to be processed.
  """
  def has_active_uploads?(socket) do
    case Map.get(socket.assigns, :uploads) do
      nil ->
        false

      uploads when is_map(uploads) ->
        # For now, just check if there are any uploads configured
        # The uploads structure seems to have changed, so we'll be conservative
        map_size(uploads) > 0

      _ ->
        # Invalid uploads value
        false
    end
  end

  @doc """
  Waits for all active uploads to complete before proceeding.
  """
  def wait_for_uploads_to_complete(socket, max_wait_time \\ 5000) do
    start_time = System.monotonic_time(:millisecond)
    wait_for_uploads_to_complete_loop(socket, start_time, max_wait_time)
  end

  defp wait_for_uploads_to_complete_loop(socket, start_time, max_wait_time) do
    current_time = System.monotonic_time(:millisecond)
    elapsed = current_time - start_time

    if elapsed >= max_wait_time do
      Logger.warning("Timeout waiting for uploads to complete after #{max_wait_time}ms")
      socket
    else
      if has_active_uploads?(socket) do
        Process.sleep(50)
        wait_for_uploads_to_complete_loop(socket, start_time, max_wait_time)
      else
        socket
      end
    end
  end

  defp consume_active_entries(socket, upload_key, active_entries) do
    # Consume all active entries for this upload
    Enum.reduce(active_entries, socket, fn entry, acc_socket ->
      if entry.done? do
        # Entry is done, consume it
        Phoenix.LiveView.consume_uploaded_entries(acc_socket, upload_key, fn _meta, upload_entry ->
          if upload_entry.ref == entry.ref do
            # This is the entry we want to consume
            Logger.info("Consuming active upload entry: #{upload_entry.client_name}")
            {:ok, nil}  # Discard the file since we're just cleaning up
          else
            # Skip other entries
            {:postpone, nil}
          end
        end)
      else
        # Entry is not done, cancel it
        Phoenix.LiveView.cancel_upload(acc_socket, upload_key, entry.ref)
      end
    end)
  end

  @doc """
  Gets upload entries for a specific entry.
  """
  def get_upload_entries_for_entry(entry, uploads) do
    upload_key = get_upload_key_for_entry(entry)
    upload_config = Map.get(uploads, upload_key, %{entries: []})
    upload_config.entries
  end

  @doc """
  Checks if entry has uploaded files.
  """
  def entry_has_uploaded_files?(entry, uploads) do
    entry.photos_uploaded > 0 or
      (
        upload_key = get_upload_key_for_entry(entry)
        upload_config = Map.get(uploads, upload_key, %{entries: []})
        upload_config.entries != []
      )
  end

  # Private functions

  defp handle_successful_uploads(socket, entry, file_info_list) do
    # Update the entry with new file information (append to existing photos)
    new_photo_paths = Enum.map(file_info_list, & &1.path)
    new_photo_web_paths = Enum.map(file_info_list, & &1.web_path)

    new_photo_entries =
      Enum.map(file_info_list, fn info ->
        %{client_name: info.filename, client_size: info.size}
      end)

    # Create database entry if this is the first photo for this entry
    final_entry_id =
      if length(file_info_list) > 0 do
        create_or_update_database_entry(socket, entry, file_info_list)
      else
        entry.id
      end

    updated_entry = %{
      entry
      | id: final_entry_id,
        photos_uploaded: entry.photos_uploaded + length(file_info_list),
        photo_paths: entry.photo_paths ++ new_photo_paths,
        photo_web_paths: entry.photo_web_paths ++ new_photo_web_paths,
        photo_entries: entry.photo_entries ++ new_photo_entries
    }

    # Cancel any existing countdown first
    send(self(), {:cancel_analysis_timer, updated_entry.id})

    # Replace entry in the list, handling ID changes
    updated_entries =
      EntryManager.replace_entry_by_original_id(socket.assigns.entries, entry.id, updated_entry)

    # Start debounce timer for AI analysis instead of immediate analysis
    start_analysis_debounce(updated_entry.id)

    photo_count = length(file_info_list)
    total_photos = updated_entry.photos_uploaded

    # Return the updated entries and flash message for the LiveView to handle
    {updated_entries,
     {:info,
      "#{photo_count} photo(s) uploaded for entry #{entry.number}! Total: #{total_photos}/3. Starting analysis..."}}
  end

  defp create_or_update_database_entry(socket, entry, file_info_list) do
    Logger.info(
      "Creating/updating database entry for #{entry.id} with #{length(file_info_list)} new photos"
    )

    # Check if this entry already exists in the database
    case safe_get_entry(entry.id) do
      {:ok, db_entry} ->
        # Entry exists, create EntryImage records for new photos
        add_images_to_existing_entry(db_entry, file_info_list)
        entry.id

      {:error, :not_found} ->
        # Entry doesn't exist, create new one
        create_new_database_entry(socket, entry, file_info_list)

      {:error, :invalid_id} ->
        # String ID like "entry_6311", create new DB entry
        create_new_database_entry(socket, entry, file_info_list)
    end
  end

  defp add_images_to_existing_entry(db_entry, file_info_list) do
    Logger.info("Adding #{length(file_info_list)} images to existing entry #{db_entry.id}")

    # Get current image count for upload_order
    current_image_count = length(Medpack.BatchProcessing.list_entry_images(db_entry.id))

    # Create EntryImage records for each new photo
    Enum.with_index(file_info_list, current_image_count)
    |> Enum.each(fn {file_info, index} ->
      case Medpack.BatchProcessing.create_entry_image(%{
             batch_entry_id: db_entry.id,
             s3_key: file_info.path,
             original_filename: file_info.filename,
             file_size: file_info.size,
             content_type: get_content_type(file_info.filename),
             upload_order: index
           }) do
        {:ok, _image} ->
          Logger.info("Created image record for #{file_info.filename}")

        {:error, reason} ->
          Logger.error("Failed to create image record: #{inspect(reason)}")
      end
    end)
  end

  defp create_new_database_entry(_socket, entry, file_info_list) do
    Logger.info("Creating new database entry for ID #{entry.id}")

    case Medpack.BatchProcessing.create_entry(%{
           entry_number: entry.number,
           ai_analysis_status: :pending
         }) do
      {:ok, db_entry} ->
        Logger.info("Created database entry with ID #{db_entry.id}")

        # Create EntryImage records for photos
        Enum.with_index(file_info_list)
        |> Enum.each(fn {file_info, index} ->
          case Medpack.BatchProcessing.create_entry_image(%{
                 batch_entry_id: db_entry.id,
                 s3_key: file_info.path,
                 original_filename: file_info.filename,
                 file_size: file_info.size,
                 content_type: get_content_type(file_info.filename),
                 upload_order: index
               }) do
            {:ok, _image} ->
              Logger.info("Created image record for #{file_info.filename}")

            {:error, reason} ->
              Logger.error("Failed to create image record: #{inspect(reason)}")
          end
        end)

        # Return the database entry ID
        db_entry.id

      {:error, reason} ->
        Logger.error("Failed to create database entry: #{inspect(reason)}")
        entry.id
    end
  end

  defp find_entry_by_upload_config(entries, upload_config_name) do
    # The upload_config_name is an atom like :entry_<uuid>_photos
    upload_config_str = Atom.to_string(upload_config_name)

    case Regex.run(~r/entry_([\w-]+)_photos/, upload_config_str) do
      [_, uuid] ->
        Enum.find(entries, &(&1.id == uuid))

      _ ->
        nil
    end
  end

  defp safe_get_entry(entry_id) when is_binary(entry_id) do
    # Check if it's a UUID format
    if String.length(entry_id) == 36 and String.contains?(entry_id, "-") do
      try do
        {:ok, Medpack.BatchProcessing.get_entry!(entry_id)}
      rescue
        Ecto.NoResultsError -> {:error, :not_found}
      end
    else
      # String IDs like "entry_6311" don't exist in database
      {:error, :invalid_id}
    end
  end

  defp safe_get_entry(_entry_id) do
    {:error, :invalid_id}
  end

  defp start_analysis_debounce(entry_id) do
    # Cancel any existing timer for this entry
    send(self(), {:cancel_analysis_timer, entry_id})

    # Start countdown
    send(self(), {:start_analysis_countdown, entry_id, 5})
  end

  defp get_content_type(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      _ -> "image/jpeg"
    end
  end
end
