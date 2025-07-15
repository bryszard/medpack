defmodule Medpack.BatchProcessing.EntryImage do
  use Ecto.Schema
  import Ecto.Changeset

  alias Medpack.BatchProcessing.Entry

  @foreign_key_type :binary_id

  schema "batch_entry_images" do
    belongs_to :batch_entry, Entry
    field :s3_key, :string
    field :original_filename, :string
    field :file_size, :integer
    field :content_type, :string
    field :upload_order, :integer, default: 0

    timestamps()
  end

  @doc false
  def changeset(entry_image, attrs) do
    entry_image
    |> cast(attrs, [
      :batch_entry_id,
      :s3_key,
      :original_filename,
      :file_size,
      :content_type,
      :upload_order
    ])
    |> validate_required([:batch_entry_id, :s3_key, :original_filename])
    |> validate_number(:file_size, greater_than: 0)
    |> validate_number(:upload_order, greater_than_or_equal_to: 0)
    |> validate_inclusion(:content_type, ["image/jpeg", "image/png", "image/jpg"])
    |> foreign_key_constraint(:batch_entry_id)
  end

  @doc """
  Returns the full S3 URL for this image.
  """
  def get_s3_url(%__MODULE__{s3_key: s3_key}) do
    if Medpack.FileManager.use_s3_storage?() do
      Medpack.S3FileManager.get_presigned_url(s3_key)
    else
      # For local storage, convert s3_key to local path
      "/uploads/" <> Path.basename(s3_key)
    end
  end

  @doc """
  Returns a human-readable file size.
  """
  def human_file_size(%__MODULE__{file_size: nil}), do: "Unknown size"
  def human_file_size(%__MODULE__{file_size: size}) when size < 1024, do: "#{size} B"

  def human_file_size(%__MODULE__{file_size: size}) when size < 1024 * 1024 do
    "#{Float.round(size / 1024, 1)} KB"
  end

  def human_file_size(%__MODULE__{file_size: size}) do
    "#{Float.round(size / (1024 * 1024), 1)} MB"
  end
end
