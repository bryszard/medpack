defmodule Medpack.TempFile do
  @moduledoc """
  Helper module for managing temporary files during processing operations.

  Ensures proper cleanup of temporary files even if errors occur.
  """

  @enforce_keys ~w|path|a
  defstruct [:path]

  @doc """
  Creates a temporary file and ensures it's cleaned up after the callback completes.

  The callback receives a TempFile struct with the path to use.
  The temporary file is automatically removed after the callback completes,
  even if an error is raised.

  ## Examples

      TempFile.with_temp_file(".jpg", fn temp_file ->
        File.write!(temp_file.path, image_content)
        process_image(temp_file.path)
      end)
  """
  def with_temp_file(extension, callback) do
    temp_file = %__MODULE__{path: generate_path(extension)}

    try do
      result = callback.(temp_file)
      remove_file(temp_file)
      result
    rescue
      error ->
        remove_file(temp_file)
        reraise error, __STACKTRACE__
    end
  end

  # Private functions

  defp generate_path(nil), do: generate_path("")
  defp generate_path(extension), do: Path.join(System.tmp_dir!(), Ecto.UUID.generate() <> extension)

  defp remove_file(%__MODULE__{path: path}) do
    if File.exists?(path) do
      File.rm!(path)
    end
  end
end
