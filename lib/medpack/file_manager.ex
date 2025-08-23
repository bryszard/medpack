defmodule Medpack.FileManager do
  @moduledoc """
  Handles file uploads, storage, and cleanup for medicine photos.
  Automatically chooses between local storage (development) and S3 storage (production).
  """

  require Logger
  alias Medpack.S3FileManager

  @allowed_extensions [".jpg", ".jpeg", ".png"]
  # 50MB
  @max_file_size 50_000_000

  @doc """
  Saves an auto-uploaded file (from consume_uploaded_entries) to the appropriate location.

  For auto-uploaded files, the file content is provided via the meta parameter from consume_uploaded_entries.
  Returns {:ok, result} where result is either file_path (local) or %{s3_key: key, url: url} (S3)
  """
  def save_auto_uploaded_file(meta, upload_entry, entry_id) do
    if use_s3_storage?() do
      S3FileManager.save_auto_uploaded_file(meta, upload_entry, entry_id)
    else
      save_auto_uploaded_file_locally(meta, upload_entry, entry_id)
    end
  end

  @doc """
  Saves an auto-uploaded file locally (development mode).
  For auto-uploads, the file content is available via meta.path.
  """
  def save_auto_uploaded_file_locally(meta, upload_entry, entry_id) do
    with :ok <- validate_auto_upload(upload_entry),
         {:ok, file_path} <- generate_file_path(upload_entry, entry_id),
         :ok <- ensure_directory_exists(file_path),
         {:ok, _} <- copy_file(meta.path, file_path) do
      # Return a relative path that can be consistently processed
      relative_path = get_relative_path(file_path)
      {:ok, relative_path}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates an uploaded file.
  """
  def validate_upload(upload_entry) do
    if use_s3_storage?() do
      S3FileManager.validate_upload(upload_entry)
    else
      validate_upload_locally(upload_entry)
    end
  end

  @doc """
  Validates an uploaded file for local storage.
  """
  def validate_upload_locally(upload_entry) do
    with :ok <- validate_file_size(upload_entry),
         :ok <- validate_file_extension(upload_entry),
         :ok <- validate_file_exists(upload_entry) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates an auto-uploaded file (from consume_uploaded_entries).
  """
  def validate_auto_upload(upload_entry) do
    with :ok <- validate_auto_file_size(upload_entry),
         :ok <- validate_file_extension(upload_entry),
         :ok <- validate_auto_upload_complete(upload_entry) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a file from storage.
  """
  def delete_file(file_identifier) when is_binary(file_identifier) do
    if use_s3_storage?() do
      # In S3 mode, file_identifier is the S3 key
      S3FileManager.delete_file(file_identifier)
    else
      # In local mode, file_identifier is the file path
      delete_file_locally(file_identifier)
    end
  end

  @doc """
  Deletes a file from local storage.
  """
  def delete_file_locally(file_path) when is_binary(file_path) do
    # Convert to absolute path based on the format
    absolute_path =
      cond do
        # Already an absolute path containing priv/static
        String.contains?(file_path, "priv/static") ->
          file_path

        # Web path starting with /uploads/
        String.starts_with?(file_path, "/uploads/") ->
          # Convert web path to absolute path
          relative_path = String.replace_prefix(file_path, "/uploads/", "")
          upload_path = get_upload_path()
          Path.join([upload_path, relative_path])

        # Relative path from uploads directory
        String.starts_with?(file_path, "uploads/") ->
          upload_path = get_upload_path()
          Path.join([upload_path, String.replace_prefix(file_path, "uploads/", "")])

        # Just a filename
        true ->
          upload_path = get_upload_path()
          Path.join([upload_path, file_path])
      end

    case File.rm(absolute_path) do
      :ok ->
        Logger.info("Deleted file: #{absolute_path}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to delete file #{absolute_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Cleans up temporary files older than the specified age.
  """
  def cleanup_temp_files(max_age_hours \\ 24) do
    temp_path = get_temp_upload_path()
    cutoff_time = DateTime.utc_now() |> DateTime.add(-max_age_hours * 3600, :second)

    case File.ls(temp_path) do
      {:ok, files} ->
        files
        |> Enum.map(&Path.join(temp_path, &1))
        |> Enum.filter(&File.regular?/1)
        |> Enum.filter(fn file_path ->
          case File.stat(file_path) do
            {:ok, %{mtime: mtime}} ->
              file_time = mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
              DateTime.compare(file_time, cutoff_time) == :lt

            _ ->
              false
          end
        end)
        |> Enum.each(&delete_file/1)

        :ok

      {:error, reason} ->
        Logger.warning("Failed to list temp files: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets the content type for a file based on its extension.
  """
  def get_content_type(filename) when is_binary(filename) do
    if use_s3_storage?() do
      S3FileManager.get_content_type(filename)
    else
      get_content_type_locally(filename)
    end
  end

  @doc """
  Gets the content type for a file based on its extension (local implementation).
  """
  def get_content_type_locally(filename) when is_binary(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      _ -> "application/octet-stream"
    end
  end

  @doc """
  Generates a unique filename for an uploaded file.
  """
  def generate_unique_filename(original_filename) do
    if use_s3_storage?() do
      S3FileManager.generate_unique_filename(original_filename)
    else
      generate_unique_filename_locally(original_filename)
    end
  end

  @doc """
  Generates a unique filename for an uploaded file (local implementation).
  """
  def generate_unique_filename_locally(original_filename) do
    extension = Path.extname(original_filename)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    # Use URL-safe Base64 encoding to avoid slashes and plus signs
    random_string = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)

    "#{timestamp}_#{random_string}#{extension}"
  end

  @doc """
  Gets the URL for a photo, handling both local files and S3 objects.
  For S3, returns a proxied URL through the Phoenix app for consistent caching.
  """
  def get_photo_url(photo_path) when is_binary(photo_path) do
    if use_s3_storage?() do
      # For S3, return a proxied URL through the Phoenix app
      # This provides consistent URLs and better caching
      extract_filename_from_path(photo_path)
      |> then(fn filename -> "/images/#{filename}" end)
    else
      cond do
        # Full absolute path (starts with absolute directory)
        String.contains?(photo_path, "priv/static") ->
          photo_path
          |> String.replace(~r/.*priv\/static/, "")
          |> then(fn path ->
            if String.starts_with?(path, "/") do
              path
            else
              "/" <> path
            end
          end)

        # Already a web path (starts with /)
        String.starts_with?(photo_path, "/") ->
          photo_path

        # Relative path from priv/static (e.g., "uploads/2025-07-03/file.jpg")
        String.starts_with?(photo_path, "uploads/") ->
          "/" <> photo_path

        # Legacy filename only (e.g., "entry_123_456.jpg")
        true ->
          "/uploads/" <> photo_path
      end
    end
  end

  def get_photo_url(_), do: nil

  @doc """
  Gets the content of a file from storage, handling both local files and S3 objects.
  Returns {:ok, content, content_type} or {:error, reason}.
  """
  def get_file_content(file_identifier) when is_binary(file_identifier) do
    if use_s3_storage?() do
      S3FileManager.get_file_content(file_identifier)
    else
      get_file_content_locally(file_identifier)
    end
  end

  def get_file_content(_), do: {:error, :invalid_identifier}

  defp get_file_content_locally(file_path) do
    # For local storage, construct the full path to the file in priv/static/uploads/
    full_path = Path.join([priv_static_uploads_path(), file_path])

    case File.read(full_path) do
      {:ok, content} ->
        content_type = get_content_type_from_path(file_path)
        {:ok, content, content_type}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp priv_static_uploads_path do
    Application.get_env(:medpack, :upload_path) ||
      Path.expand("priv/static/uploads", :code.priv_dir(:medpack))
  end

  defp get_content_type_from_path(file_path) do
    case Path.extname(file_path) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      _ -> "application/octet-stream"
    end
  end

  defp extract_filename_from_path(path) do
    path
    |> String.split("/")
    |> List.last()
  end

  @doc """
  Determines whether to use S3 storage based on configuration.
  """
  def use_s3_storage? do
    Application.get_env(:medpack, :file_storage_backend, :local) == :s3
  end

  # Private functions

  defp validate_file_size(upload_entry) do
    # For auto-uploaded entries, use client_size; for manual uploads, use file stat
    size =
      if Map.has_key?(upload_entry, :path) do
        case File.stat(upload_entry.path) do
          {:ok, %{size: size}} -> size
          {:error, reason} -> {:error, "Cannot read file stats: #{inspect(reason)}"}
        end
      else
        # Auto-uploaded entries have client_size
        upload_entry.client_size
      end

    if size <= @max_file_size do
      :ok
    else
      {:error, "File too large: #{size} bytes (max: #{@max_file_size})"}
    end
  end

  defp validate_file_extension(upload_entry) do
    extension = Path.extname(upload_entry.client_name) |> String.downcase()

    if extension in @allowed_extensions do
      :ok
    else
      {:error,
       "Invalid file extension: #{extension}. Allowed: #{Enum.join(@allowed_extensions, ", ")}"}
    end
  end

  defp validate_file_exists(upload_entry) do
    # For auto-uploaded entries, we can't check file existence since they don't have a path
    # The file content is handled by Phoenix LiveView's consume_uploaded_entries
    if Map.has_key?(upload_entry, :path) do
      if File.exists?(upload_entry.path) do
        :ok
      else
        {:error, "Uploaded file does not exist"}
      end
    else
      # Auto-uploaded entries are valid if they're marked as done
      if upload_entry.done? do
        :ok
      else
        {:error, "Upload not complete"}
      end
    end
  end

  defp validate_auto_file_size(upload_entry) do
    # Auto-uploaded entries use client_size
    size = upload_entry.client_size

    if size <= @max_file_size do
      :ok
    else
      {:error, "File too large: #{size} bytes (max: #{@max_file_size})"}
    end
  end

  defp validate_auto_upload_complete(upload_entry) do
    if upload_entry.done? do
      :ok
    else
      {:error, "Upload not complete"}
    end
  end

  defp generate_file_path(upload_entry, entry_id) do
    unique_filename = generate_unique_filename(upload_entry.client_name)
    upload_path = get_upload_path()

    # Organize by date for better file management
    date_folder = Date.utc_today() |> Date.to_string()

    # Clean entry_id to avoid double prefixes and ensure it's safe for file paths
    clean_entry_id =
      entry_id
      |> to_string()
      # Remove "entry_" prefix if present
      |> String.replace(~r/^entry_/, "")
      # Replace unsafe characters with underscores
      |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")

    file_path =
      Path.join([upload_path, date_folder, "entry_#{clean_entry_id}_#{unique_filename}"])

    {:ok, file_path}
  end

  defp ensure_directory_exists(file_path) do
    dir_path = Path.dirname(file_path)

    case File.mkdir_p(dir_path) do
      :ok -> :ok
      {:error, reason} -> {:error, "Cannot create directory: #{inspect(reason)}"}
    end
  end

  defp copy_file(source_path, dest_path) do
    case File.cp(source_path, dest_path) do
      :ok -> {:ok, dest_path}
      {:error, reason} -> {:error, "Cannot copy file: #{inspect(reason)}"}
    end
  end

  def get_upload_path do
    Application.get_env(:medpack, :upload_path, "uploads")
  end

  defp get_temp_upload_path do
    Application.get_env(:medpack, :temp_upload_path, "tmp/uploads")
  end

  # Helper function to convert absolute file paths to relative paths
  # that can be consistently processed by get_photo_url
  defp get_relative_path(absolute_path) when is_binary(absolute_path) do
    # Convert absolute path to relative from priv/static
    case String.split(absolute_path, "priv/static/") do
      [_prefix, suffix] -> suffix
      # fallback to original if pattern doesn't match
      _ -> absolute_path
    end
  end

  @doc """
  Resolves a stored file path to an absolute filesystem path for local storage.

  For local storage, files are stored with relative paths from priv/static/
  like "uploads/2025-07-09/file.jpg" and need to be resolved to absolute paths
  like "priv/static/uploads/2025-07-09/file.jpg" for file operations.

  For S3 storage, returns the path as-is since it's an S3 key.
  """
  def resolve_file_path(stored_path) do
    if use_s3_storage?() do
      # For S3, the stored path is the S3 key - return as-is
      stored_path
    else
      # For local storage, resolve to absolute filesystem path
      if String.starts_with?(stored_path, "/") do
        # Already absolute path
        stored_path
      else
        # Relative path from priv/static/ - resolve it
        Path.join(["priv", "static", stored_path])
      end
    end
  end
end
