defmodule MedpackWeb.ImageController do
  use MedpackWeb, :controller

  alias Medpack.FileManager

  @doc """
  Serves images from Tigris storage through the Phoenix app.
  This provides consistent URLs and better caching while maintaining security.
  
  Supports size parameter for serving optimized image sizes:
  - ?size=200 for 200px width thumbnails
  - ?size=450 for 450px width previews  
  - ?size=600 for 600px width enlarged views
  - No size parameter serves original
  """
  def show(conn, %{"path" => path} = params) do
    size = Map.get(params, "size", "original")
    
    # Generate the appropriate file path based on size
    s3_key = case size do
      "original" -> "medicines/#{path}"
      _ -> generate_sized_s3_key(path, size)
    end

    case FileManager.get_file_content(s3_key) do
      {:ok, content, content_type} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=31536000")  # Cache for 1 year
        |> put_resp_header("etag", generate_etag(content))
        |> put_resp_content_type(content_type)
        |> send_resp(200, content)

      {:error, :not_found} ->
        # If sized version not found, try to serve original as fallback
        if size != "original" do
          fallback_s3_key = "medicines/#{path}"
          case FileManager.get_file_content(fallback_s3_key) do
            {:ok, content, content_type} ->
              conn
              |> put_resp_header("cache-control", "public, max-age=3600")  # Shorter cache for fallbacks
              |> put_resp_header("etag", generate_etag(content))
              |> put_resp_content_type(content_type)
              |> send_resp(200, content)
              
            {:error, _} ->
              conn
              |> put_status(:not_found)
              |> text("Image not found")
          end
        else
          conn
          |> put_status(:not_found)
          |> text("Image not found")
        end

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> text("Error loading image")
    end
  end

  defp generate_etag(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp generate_sized_s3_key(path, size) do
    # Resized images are stored as WebP for optimization
    basename = Path.basename(path, Path.extname(path))
    "medicines/#{basename}_#{size}.webp"
  end
end
