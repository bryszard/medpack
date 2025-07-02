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
  Saves an uploaded file to the appropriate location.

  Returns {:ok, result} where result is either file_path (local) or %{s3_key: key, url: url} (S3)
  """
  def save_uploaded_file(upload_entry, entry_id) do
    if use_s3_storage?() do
      S3FileManager.save_uploaded_file(upload_entry, entry_id)
    else
      save_uploaded_file_locally(upload_entry, entry_id)
    end
  end

  @doc """
  Saves an uploaded file locally (development mode).
  """
  def save_uploaded_file_locally(upload_entry, entry_id) do
    with :ok <- validate_upload(upload_entry),
         {:ok, file_path} <- generate_file_path(upload_entry, entry_id),
         :ok <- ensure_directory_exists(file_path),
         {:ok, _} <- copy_file(upload_entry.path, file_path) do
      {:ok, file_path}
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
    case File.rm(file_path) do
      :ok ->
        Logger.info("Deleted file: #{file_path}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to delete file #{file_path}: #{inspect(reason)}")
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
    random_string = :crypto.strong_rand_bytes(8) |> Base.encode64(padding: false)

    "#{timestamp}_#{random_string}#{extension}"
  end

  @doc """
  Gets the URL for a photo, handling both local files and S3 objects.
  For S3, returns a presigned URL that expires in 1 hour.
  """
  def get_photo_url(photo_path) when is_binary(photo_path) do
    if use_s3_storage?() do
      # For S3, the photo_path is the S3 key - return presigned URL
      S3FileManager.get_presigned_url(photo_path)
    else
      # For local files, return the path as-is (should start with /uploads/)
      photo_path
    end
  end

  def get_photo_url(_), do: nil

  @doc """
  Determines whether to use S3 storage based on configuration.
  """
  def use_s3_storage? do
    Application.get_env(:medpack, :file_storage_backend, :local) == :s3
  end

  # Private functions

  defp validate_file_size(upload_entry) do
    case File.stat(upload_entry.path) do
      {:ok, %{size: size}} when size <= @max_file_size -> :ok
      {:ok, %{size: size}} -> {:error, "File too large: #{size} bytes (max: #{@max_file_size})"}
      {:error, reason} -> {:error, "Cannot read file stats: #{inspect(reason)}"}
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
    if File.exists?(upload_entry.path) do
      :ok
    else
      {:error, "Uploaded file does not exist"}
    end
  end

  defp generate_file_path(upload_entry, entry_id) do
    unique_filename = generate_unique_filename(upload_entry.client_name)
    upload_path = get_upload_path()

    # Organize by date for better file management
    date_folder = Date.utc_today() |> Date.to_string()

    file_path = Path.join([upload_path, date_folder, "entry_#{entry_id}_#{unique_filename}"])
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

  defp get_upload_path do
    Application.get_env(:medpack, :upload_path, "uploads")
  end

  defp get_temp_upload_path do
    Application.get_env(:medpack, :temp_upload_path, "tmp/uploads")
  end
end
