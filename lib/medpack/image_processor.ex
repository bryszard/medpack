defmodule Medpack.ImageProcessor do
  @moduledoc """
  Handles image processing operations including resizing and optimization.

  Processes images into multiple sizes:
  - 600px width: Bigger thumbnails
  - 200px width: Smaller thumbnails

  Supports both S3 and local storage backends.
  """

  require Logger
  alias Medpack.{FileManager, TempFile}

  @sizes %{
    "original" => nil,
    "600" => 600,
    "200" => 200
  }

  @doc """
  Processes an image into multiple sizes.

  Takes an image file path/key and generates resized versions.
  Returns {:ok, resized_paths_map} or {:error, reason}.
  """
  def process_image_sizes(image_path) when is_binary(image_path) do
    Logger.info("Processing image sizes for: #{image_path}")

    try do
      TempFile.with_temp_file(Path.extname(image_path), fn temp_file ->
        # Download original image to temp file
        case download_image_to_temp_file(image_path, temp_file.path) do
          :ok ->
            # Open image from temp file
            image = Image.open!(temp_file.path)

            # Generate all variants
            generate_variants(image, image_path, @sizes |> Map.to_list())

          {:error, reason} ->
            Logger.error("Failed to download image: #{reason}")
            {:error, "Failed to download image: #{reason}"}
        end
      end)
    rescue
      e ->
        Logger.error("Error processing image sizes: #{Exception.message(e)}")
        {:error, "Image processing failed: #{Exception.message(e)}"}
    end
  end

  @doc """
  Generates a resized filename for a given size.

  Resized images are saved as WebP for optimal compression and performance.

  Examples:
    original.jpg -> original_600.webp
    image.png -> image_200.webp
  """
  def generate_resized_filename(original_filename, size_name) when size_name != "original" do
    basename = Path.basename(original_filename, Path.extname(original_filename))
    "#{basename}_#{size_name}.webp"
  end

  def generate_resized_filename(original_filename, "original"), do: original_filename

  @doc """
  Generates resized file path/key for storage.
  """
  def generate_resized_path(original_path, size_name) when size_name != "original" do
    if FileManager.use_s3_storage?() do
      # For S3: medicines/image.jpg -> medicines/image_600.jpg
      generate_resized_s3_key(original_path, size_name)
    else
      # For local: uploads/medicines/image.jpg -> uploads/medicines/image_600.jpg
      generate_resized_local_path(original_path, size_name)
    end
  end

  def generate_resized_path(original_path, "original"), do: original_path

    # Private functions

  defp download_image_to_temp_file(image_path, temp_file_path) do
    if FileManager.use_s3_storage?() do
      case Medpack.S3FileManager.get_file_content(image_path) do
        {:ok, content, _content_type} ->
          File.write(temp_file_path, content)

        {:error, reason} ->
          {:error, reason}
      end
    else
      # For local storage, we need to convert the path format
      # From "/uploads/medicines/file.jpg" to "medicines/file.jpg"
      local_path = if String.starts_with?(image_path, "/uploads/") do
        String.replace_prefix(image_path, "/uploads/", "")
      else
        image_path
      end

      case FileManager.get_file_content(local_path) do
        {:ok, content, _content_type} ->
          File.write(temp_file_path, content)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Generate variants similar to the working GatAttachments implementation
  defp generate_variants(_image, original_path, []), do: {:ok, %{"original" => original_path}}

  defp generate_variants(image, original_path, [variant | variants]) do
    with {:ok, result_map} <- generate_variant(image, original_path, variant),
         {:ok, remaining_map} <- generate_variants(image, original_path, variants) do
      {:ok, Map.merge(result_map, remaining_map)}
    end
  end

  defp generate_variant(_image, original_path, {"original", _config}) do
    {:ok, %{"original" => original_path}}
  end

    defp generate_variant(image, original_path, {size_name, max_width}) do
    try do
      TempFile.with_temp_file(".webp", fn temp_file ->
        # Resize using Image.thumbnail! which is optimized for this use case
        resized_image = Image.thumbnail!(image, max_width, resize: :down)

                # Write as WebP with optimization options
        webp_options = [
          webp: [
            quality: 80,            # Good balance of quality vs size
            effort: 6               # CPU effort for compression (0-6, higher = better compression)
          ]
        ]

        Image.write!(resized_image, temp_file.path, webp_options)
        Logger.debug("Converted #{size_name}px variant to WebP with optimization")

        # Generate final path and upload/save
        resized_path = generate_resized_path(original_path, size_name)

        case save_resized_image_from_file(temp_file.path, resized_path) do
          {:ok, saved_path} ->
            Logger.debug("Successfully generated #{size_name}px variant: #{saved_path}")
            {:ok, %{size_name => saved_path}}

          {:error, reason} ->
            Logger.error("Failed to save #{size_name}px variant: #{reason}")
            {:error, reason}
        end
      end)
    rescue
      e ->
        Logger.error("Exception generating #{size_name}px variant: #{Exception.message(e)}")
        {:error, "Variant generation failed: #{Exception.message(e)}"}
    end
  end

  # Save resized image from temp file to final location
  defp save_resized_image_from_file(temp_file_path, final_path) do
    if FileManager.use_s3_storage?() do
      save_resized_image_to_s3_from_file(temp_file_path, final_path)
    else
      save_resized_image_locally_from_file(temp_file_path, final_path)
    end
  end

  defp save_resized_image_to_s3_from_file(temp_file_path, s3_key) do
    content_type = "image/webp"

    case Medpack.S3FileManager.save_file_with_key(temp_file_path, s3_key, content_type) do
      {:ok, %{s3_key: ^s3_key}} -> {:ok, s3_key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp save_resized_image_locally_from_file(temp_file_path, file_path) do
    # Resolve to absolute path
    absolute_path = FileManager.resolve_file_path(file_path)

    # Ensure directory exists
    dir_path = Path.dirname(absolute_path)
    case File.mkdir_p(dir_path) do
      :ok ->
        case File.cp(temp_file_path, absolute_path) do
          :ok -> {:ok, file_path}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_resized_s3_key(original_key, size_name) do
    # medicines/image.jpg -> medicines/image_600.webp
    basename = Path.basename(original_key, Path.extname(original_key))
    directory = Path.dirname(original_key)

    Path.join(directory, "#{basename}_#{size_name}.webp")
  end

  defp generate_resized_local_path(original_path, size_name) do
    # /uploads/medicines/image.jpg -> uploads/medicines/image_600.webp
    # Remove leading slash to ensure it's treated as relative path
    basename = Path.basename(original_path, Path.extname(original_path))
    directory = Path.dirname(original_path)

    resized_path = Path.join(directory, "#{basename}_#{size_name}.webp")

    # Remove leading slash if present to ensure relative path
    if String.starts_with?(resized_path, "/") do
      String.slice(resized_path, 1..-1//1)
    else
      resized_path
    end
  end
end
