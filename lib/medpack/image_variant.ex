defmodule Medpack.ImageVariant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "image_variants" do
    belongs_to :medicine, Medpack.Medicine
    field :original_path, :string
    field :variant_size, :string
    field :variant_path, :string
    field :processing_status, :string, default: "pending"
    field :processing_error, :string
    field :processed_at, :utc_datetime

    timestamps()
  end

  @doc false
  def changeset(image_variant, attrs) do
    image_variant
    |> cast(attrs, [
      :medicine_id,
      :original_path,
      :variant_size,
      :variant_path,
      :processing_status,
      :processing_error,
      :processed_at
    ])
    |> validate_required([
      :medicine_id,
      :original_path,
      :variant_size,
      :variant_path,
      :processing_status
    ])
    |> validate_inclusion(:variant_size, ["original", "200", "600"])
    |> validate_inclusion(:processing_status, ["pending", "processing", "completed", "failed"])
    |> foreign_key_constraint(:medicine_id)
    |> unique_constraint([:medicine_id, :original_path, :variant_size])
  end

  @doc """
  Creates a changeset for a new image variant.
  """
  def create_changeset(attrs \\ %{}) do
    %__MODULE__{} |> changeset(attrs)
  end

  @doc """
  Creates a changeset for updating processing status.
  """
  def status_changeset(image_variant, attrs) do
    image_variant
    |> cast(attrs, [:processing_status, :processing_error, :processed_at])
    |> validate_inclusion(:processing_status, ["pending", "processing", "completed", "failed"])
  end

  @doc """
  Returns true if the variant is completed.
  """
  def completed?(%__MODULE__{processing_status: "completed"}), do: true
  def completed?(_), do: false

  @doc """
  Returns true if the variant failed processing.
  """
  def failed?(%__MODULE__{processing_status: "failed"}), do: true
  def failed?(_), do: false

  @doc """
  Returns true if the variant is pending or processing.
  """
  def pending?(%__MODULE__{processing_status: status}) when status in ["pending", "processing"], do: true
  def pending?(_), do: false
end
