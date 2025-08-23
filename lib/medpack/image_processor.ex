defmodule Medpack.ImageProcessor do
  @moduledoc """
  Handles image processing operations including resizing and optimization.
  
  Processes images into multiple sizes:
  - 600px width: Enlarged/modal views
  - 450px width: Card view thumbnails  
  - 200px width: Table view & non-focused detail photos
  
  Supports both S3 and local storage backends.
  """

  require Logger
  alias Medpack.FileManager

  @sizes %{
    "original" => nil,
    "600" => 600,
    "450" => 450, 
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
      # Read the image content
      case read_image_content(image_path) do
        {:ok, image_content, content_type} ->
          # Process all sizes except original
          resize_results = 
            @sizes
            |> Enum.reject(fn {size_name, _} -> size_name == "original" end)
            |> Enum.map(fn {size_name, width} ->
              {size_name, resize_and_save_image(image_content, image_path, size_name, width, content_type)}
            end)
          
          # Check if all resizes were successful
          case all_successful?(resize_results) do
            true ->
              resized_paths = 
                resize_results
                |> Enum.into(%{})
                |> Map.put("original", image_path)
              
              Logger.info("Successfully processed #{map_size(resized_paths)} image sizes")
              {:ok, resized_paths}
              
            false ->
              # Clean up any successful resizes
              cleanup_failed_resizes(resize_results)
              {:error, "Failed to resize one or more image sizes"}
          end
          
        {:error, reason} ->
          Logger.error("Failed to read image content: #{reason}")
          {:error, "Failed to read image: #{reason}"}
      end
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
    image.png -> image_450.webp
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

  defp read_image_content(image_path) do
    if FileManager.use_s3_storage?() do
      Medpack.S3FileManager.get_file_content(image_path)
    else
      FileManager.get_file_content(image_path)
    end
  end

  defp convert_to_webp(image) do
    try do
      # Convert to WebP with optimal settings for web delivery
      webp_options = [
        quality: 80,              # Good balance of quality vs size
        minimize_file_size: true, # Enable advanced compression
        effort: 6,                # CPU effort for compression (1-10, default 4)
        strip_metadata: true      # Remove metadata for smaller files
      ]
      
      # Write to memory as WebP
      case Image.write(image, :memory, webp_options) do
        {:ok, webp_content} ->
          Logger.debug("Successfully converted image to WebP (#{byte_size(webp_content)} bytes)")
          {:ok, webp_content}
          
        {:error, reason} ->
          Logger.error("Failed to convert image to WebP: #{reason}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception during WebP conversion: #{Exception.message(e)}")
        {:error, "WebP conversion failed: #{Exception.message(e)}"}
    end
  end

  defp resize_and_save_image(image_content, original_path, size_name, width, _content_type) do
    try do
      # Resize the image using the Image library
      case Image.resize(image_content, width) do
        {:ok, resized_image} ->
          # Convert resized image to WebP with optimization
          case convert_to_webp(resized_image) do
            {:ok, webp_content} ->
              # Generate the resized path (will have .webp extension)
              resized_path = generate_resized_path(original_path, size_name)
              
              # Save the resized WebP image
              case save_resized_image(resized_path, webp_content, "image/webp") do
                {:ok, saved_path} ->
                  Logger.debug("Successfully resized and saved #{size_name}px WebP version: #{saved_path}")
                  {:ok, saved_path}
                  
                {:error, reason} ->
                  Logger.error("Failed to save resized WebP image #{size_name}: #{reason}")
                  {:error, reason}
              end
              
            {:error, reason} ->
              Logger.error("Failed to convert to WebP for size #{size_name}: #{reason}")
              {:error, reason}
          end
          
        {:error, reason} ->
          Logger.error("Failed to resize image to #{width}px: #{reason}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception while resizing image to #{width}px: #{Exception.message(e)}")
        {:error, "Resize failed: #{Exception.message(e)}"}
    end
  end

  defp save_resized_image(resized_path, image_content, content_type) do
    if FileManager.use_s3_storage?() do
      save_resized_image_to_s3(resized_path, image_content, content_type)
    else
      save_resized_image_locally(resized_path, image_content)
    end
  end

  defp save_resized_image_to_s3(s3_key, image_content, content_type) do
    # Write image content to a temporary file first
    temp_file = System.tmp_dir!() |> Path.join("resize_#{System.unique_integer()}.tmp")
    
    case File.write(temp_file, image_content) do
      :ok ->
        result = Medpack.S3FileManager.save_file_with_key(temp_file, s3_key, content_type)
        File.rm(temp_file)
        
        case result do
          {:ok, %{s3_key: ^s3_key}} -> {:ok, s3_key}
          {:error, reason} -> {:error, reason}
        end
        
      {:error, reason} ->
        {:error, "Failed to write temp file: #{reason}"}
    end
  end

  defp save_resized_image_locally(file_path, image_content) do
    # Resolve to absolute path
    absolute_path = FileManager.resolve_file_path(file_path)
    
    # Ensure directory exists
    dir_path = Path.dirname(absolute_path)
    case File.mkdir_p(dir_path) do
      :ok ->
        case File.write(absolute_path, image_content) do
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
    # uploads/medicines/image.jpg -> uploads/medicines/image_600.webp
    basename = Path.basename(original_path, Path.extname(original_path))
    directory = Path.dirname(original_path)
    
    Path.join(directory, "#{basename}_#{size_name}.webp")
  end

  defp all_successful?(results) do
    Enum.all?(results, fn {_size, result} -> match?({:ok, _}, result) end)
  end

  defp cleanup_failed_resizes(results) do
    results
    |> Enum.filter(fn {_size, result} -> match?({:ok, _}, result) end)
    |> Enum.each(fn {_size, {:ok, path}} ->
      FileManager.delete_file(path)
    end)
  end
end