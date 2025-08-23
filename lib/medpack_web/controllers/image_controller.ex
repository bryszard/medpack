defmodule MedpackWeb.ImageController do
  use MedpackWeb, :controller

  alias Medpack.FileManager

  @doc """
  Serves images from Tigris storage through the Phoenix app.
  This provides consistent URLs and better caching while maintaining security.
  """
  def show(conn, %{"path" => path}) do
    # Construct the full S3 key from the path
    s3_key = "medicines/#{path}"

    case FileManager.get_file_content(s3_key) do
      {:ok, content, content_type} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=31536000")  # Cache for 1 year
        |> put_resp_header("etag", generate_etag(content))
        |> put_resp_content_type(content_type)
        |> send_resp(200, content)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> text("Image not found")

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
end
