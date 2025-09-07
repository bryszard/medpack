defmodule Medpack.ImageVariants do
  @moduledoc """
  The ImageVariants context for managing image variants.
  """

  import Ecto.Query, warn: false
  alias Medpack.Repo
  alias Medpack.ImageVariant

  @doc """
  Returns the list of image variants for a medicine.
  """
  def list_image_variants_by_medicine(medicine_id) do
    from(iv in ImageVariant,
      where: iv.medicine_id == ^medicine_id,
      order_by: [asc: iv.original_path, asc: iv.variant_size]
    )
    |> Repo.all()
  end

  @doc """
  Returns the list of image variants for a specific original path.
  """
  def list_image_variants_by_path(medicine_id, original_path) do
    from(iv in ImageVariant,
      where: iv.medicine_id == ^medicine_id and iv.original_path == ^original_path,
      order_by: [asc: iv.variant_size]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single image variant.
  """
  def get_image_variant!(id), do: Repo.get!(ImageVariant, id)

  @doc """
  Gets an image variant by medicine_id, original_path, and variant_size.
  """
  def get_image_variant(medicine_id, original_path, variant_size) do
    from(iv in ImageVariant,
      where: iv.medicine_id == ^medicine_id and
             iv.original_path == ^original_path and
             iv.variant_size == ^variant_size
    )
    |> Repo.one()
  end

  @doc """
  Creates an image variant.
  """
  def create_image_variant(attrs \\ %{}) do
    %ImageVariant{}
    |> ImageVariant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates multiple image variant records for a medicine photo.
  """
  def create_variants_for_photo(medicine_id, original_path) do
    sizes = ["original", "200", "600"]

    variants = Enum.map(sizes, fn size ->
      %{
        medicine_id: medicine_id,
        original_path: original_path,
        variant_size: size,
        variant_path: if(size == "original", do: original_path, else: generate_variant_path(original_path, size)),
        processing_status: if(size == "original", do: "completed", else: "pending")
      }
    end)

    # Insert all variants in a single transaction
    Repo.transaction(fn ->
      Enum.map(variants, fn variant_attrs ->
        case create_image_variant(variant_attrs) do
          {:ok, variant} -> variant
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Updates an image variant.
  """
  def update_image_variant(%ImageVariant{} = image_variant, attrs) do
    image_variant
    |> ImageVariant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the processing status of an image variant.
  """
  def update_processing_status(%ImageVariant{} = image_variant, status, opts \\ []) do
    attrs = %{
      processing_status: status,
      processed_at: if(status == "completed", do: DateTime.utc_now(), else: nil),
      processing_error: Keyword.get(opts, :error)
    }

    image_variant
    |> ImageVariant.status_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the variant path for a completed variant.
  """
  def update_variant_path(%ImageVariant{} = image_variant, variant_path) do
    image_variant
    |> ImageVariant.changeset(%{variant_path: variant_path})
    |> Repo.update()
  end

  @doc """
  Deletes an image variant.
  """
  def delete_image_variant(%ImageVariant{} = image_variant) do
    Repo.delete(image_variant)
  end

  @doc """
  Deletes all image variants for a medicine.
  """
  def delete_image_variants_for_medicine(medicine_id) do
    from(iv in ImageVariant, where: iv.medicine_id == ^medicine_id)
    |> Repo.delete_all()
  end

  @doc """
  Returns the count of pending variants for a medicine.
  """
  def count_pending_variants(medicine_id) do
    from(iv in ImageVariant,
      where: iv.medicine_id == ^medicine_id and iv.processing_status in ["pending", "processing"],
      select: count()
    )
    |> Repo.one()
  end

  @doc """
  Returns the count of failed variants for a medicine.
  """
  def count_failed_variants(medicine_id) do
    from(iv in ImageVariant,
      where: iv.medicine_id == ^medicine_id and iv.processing_status == "failed",
      select: count()
    )
    |> Repo.one()
  end

  @doc """
  Gets the next pending variant to process.
  """
  def get_next_pending_variant do
    from(iv in ImageVariant,
      where: iv.processing_status == "pending",
      order_by: [asc: iv.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets all pending variants for processing.
  """
  def get_pending_variants(limit \\ 10) do
    from(iv in ImageVariant,
      where: iv.processing_status == "pending",
      order_by: [asc: iv.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns a map of variant sizes to paths for a specific photo.
  """
  def get_variant_paths_map(medicine_id, original_path) do
    list_image_variants_by_path(medicine_id, original_path)
    |> Enum.into(%{}, fn variant ->
      {variant.variant_size, variant.variant_path}
    end)
  end

  @doc """
  Returns true if all variants for a photo are completed.
  """
  def all_variants_completed?(medicine_id, original_path) do
    variants = list_image_variants_by_path(medicine_id, original_path)
    Enum.all?(variants, &ImageVariant.completed?/1)
  end

  @doc """
  Returns true if any variants for a photo failed.
  """
  def any_variants_failed?(medicine_id, original_path) do
    variants = list_image_variants_by_path(medicine_id, original_path)
    Enum.any?(variants, &ImageVariant.failed?/1)
  end

  # Private functions

  defp generate_variant_path(original_path, size) when size != "original" do
    # Convert original path to variant path
    # /uploads/medicines/image.jpg -> uploads/medicines/image_200.webp
    basename = Path.basename(original_path, Path.extname(original_path))
    directory = Path.dirname(original_path)

    variant_filename = "#{basename}_#{size}.webp"
    variant_path = Path.join(directory, variant_filename)

    # Remove leading slash to ensure relative path
    if String.starts_with?(variant_path, "/") do
      String.slice(variant_path, 1..-1//1)
    else
      variant_path
    end
  end
end
