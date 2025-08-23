defmodule Medpack.S3FileManager do
  @moduledoc """
  Handles file uploads, storage, and cleanup for medicine photos using S3-compatible storage (Tigris).
  """

  require Logger
  alias ExAws.S3

  @allowed_extensions [".jpg", ".jpeg", ".png"]
  # 50MB - matching local file manager
  @max_file_size 50_000_000

  @doc """
  Saves an auto-uploaded file to S3 storage.
  For auto-uploads, the file content is available via meta.path.

  Returns {:ok, %{s3_key: key, url: url}} or {:error, reason}
  """
  def save_auto_uploaded_file(meta, upload_entry, entry_id) do
    with :ok <- validate_auto_upload(upload_entry),
         {:ok, s3_key} <- generate_s3_key(upload_entry, entry_id),
         {:ok, file_content} <- File.read(meta.path),
         {:ok, _response} <- upload_to_s3_auto(s3_key, file_content, upload_entry) do
      url = get_presigned_url(s3_key)
      {:ok, %{s3_key: s3_key, url: url}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Saves an uploaded file to S3 storage with a custom key.

  Returns {:ok, %{s3_key: key, url: url}} or {:error, reason}
  """
  def save_file_with_key(file_path, s3_key, content_type \\ nil) do
    with {:ok, file_content} <- File.read(file_path),
         content_type <- content_type || get_content_type_from_path(file_path),
         {:ok, _response} <- upload_to_s3_with_content_type(s3_key, file_content, content_type) do
      url = get_presigned_url(s3_key)
      {:ok, %{s3_key: s3_key, url: url}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates an uploaded file.
  """
  def validate_upload(upload_entry) do
    with :ok <- validate_file_size(upload_entry),
         :ok <- validate_file_extension(upload_entry),
         :ok <- validate_file_exists(upload_entry) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates an auto-uploaded file.
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
  Deletes a file from S3 storage.
  """
  def delete_file(s3_key) when is_binary(s3_key) do
    bucket_name = get_bucket_name()

    case S3.delete_object(bucket_name, s3_key) |> ExAws.request() do
      {:ok, _response} ->
        Logger.info("Deleted S3 file: #{s3_key}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to delete S3 file #{s3_key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Deletes multiple files from S3 storage.
  """
  def delete_files(s3_keys) when is_list(s3_keys) do
    bucket_name = get_bucket_name()

    delete_objects = Enum.map(s3_keys, &%{key: &1})

    case S3.delete_multiple_objects(bucket_name, delete_objects) |> ExAws.request() do
      {:ok, _response} ->
        Logger.info("Deleted #{length(s3_keys)} S3 files")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to delete S3 files: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets the content type for a file based on its extension.
  """
  def get_content_type(filename) when is_binary(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end

  @doc """
  Generates a unique S3 key for an uploaded file.
  """
  def generate_s3_key(upload_entry, entry_id) do
    unique_filename = generate_unique_filename(upload_entry.client_name)
    date_folder = Date.utc_today() |> Date.to_string()

    # Clean entry_id to avoid double prefixes and ensure it's safe for S3 keys
    clean_entry_id =
      entry_id
      |> to_string()
      # Remove "entry_" prefix if present
      |> String.replace(~r/^entry_/, "")
      # Replace unsafe characters with underscores
      |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")

    s3_key = "uploads/#{date_folder}/entry_#{clean_entry_id}_#{unique_filename}"
    {:ok, s3_key}
  end

  @doc """
  Generates a unique filename for an uploaded file.
  """
  def generate_unique_filename(original_filename) do
    extension = Path.extname(original_filename)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    # Use URL-safe Base64 encoding to avoid slashes and plus signs
    random_string = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)

    "#{timestamp}_#{random_string}#{extension}"
  end

  @doc """
  Gets a presigned URL for an S3 object that expires in 1 hour.
  """
  def get_presigned_url(s3_key, expires_in \\ 3600) do
    bucket_name = get_bucket_name()

    ExAws.Config.new(:s3)
    |> ExAws.S3.presigned_url(:get, bucket_name, s3_key, expires_in: expires_in)
    |> case do
      {:ok, url} ->
        url

      {:error, reason} ->
        Logger.error("Failed to generate presigned URL for #{s3_key}: #{inspect(reason)}")
        nil
    end
  end

    @doc """
  Gets a fixed URL for an S3 object. Access is controlled by domain restrictions.
  """
  def get_fixed_url(s3_key) when is_binary(s3_key) do
    bucket_name = get_bucket_name()

    # For Tigris, use the fly.storage.tigris.dev host
    # Access is controlled by domain restrictions in bucket policy
    "https://fly.storage.tigris.dev/#{bucket_name}/#{s3_key}"
  end

  @doc """
  Gets the content of a file from S3 storage.
  Returns {:ok, content, content_type} or {:error, reason}.
  """
  def get_file_content(s3_key) when is_binary(s3_key) do
    bucket_name = get_bucket_name()

    case S3.get_object(bucket_name, s3_key) |> ExAws.request() do
      {:ok, %{body: content, headers: headers}} ->
        content_type = get_content_type_from_headers(headers) || get_content_type_from_path(s3_key)
        {:ok, content, content_type}

      {:error, reason} ->
        Logger.error("Failed to get S3 file content for #{s3_key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_content_type_from_headers(headers) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "content-type" end)
    |> case do
      {_key, value} -> value
      nil -> nil
    end
  end

  defp get_content_type_from_path(file_path) do
    case Path.extname(file_path) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end

  @doc """
  Copies an S3 object from one key to another within the same bucket.
  """
  def copy_object(source_key, dest_key) do
    bucket_name = get_bucket_name()

    Logger.info("Copying S3 object from #{source_key} to #{dest_key}")

    case S3.put_object_copy(bucket_name, dest_key, bucket_name, source_key)
         |> ExAws.request() do
      {:ok, response} ->
        Logger.info("Successfully copied S3 object to #{dest_key}")
        {:ok, response}

      {:error, reason} ->
        Logger.error("Failed to copy S3 object: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists all objects in the bucket with a given prefix.
  """
  def list_objects(prefix \\ "") do
    bucket_name = get_bucket_name()

    case S3.list_objects(bucket_name, prefix: prefix) |> ExAws.request() do
      {:ok, %{body: %{contents: contents}}} ->
        objects =
          Enum.map(contents, fn object ->
            %{
              key: object.key,
              size: object.size,
              last_modified: object.last_modified,
              url: get_presigned_url(object.key)
            }
          end)

        {:ok, objects}

      {:error, reason} ->
        {:error, reason}
    end
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

  defp upload_to_s3_auto(s3_key, file_content, upload_entry) do
    content_type = get_content_type(upload_entry.client_name)

    upload_to_s3_with_content_type(s3_key, file_content, content_type)
  end

  defp upload_to_s3_with_content_type(s3_key, file_content, content_type) do
    bucket_name = get_bucket_name()

    S3.put_object(bucket_name, s3_key, file_content, content_type: content_type)
    |> ExAws.request()
  end



  defp get_bucket_name do
    Application.get_env(:medpack, :s3_bucket) ||
      raise "S3_BUCKET environment variable is required for S3 file storage"
  end
end
