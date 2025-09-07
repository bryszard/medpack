defmodule Medpack.Jobs.ProcessImageSizesJob do
  @moduledoc """
  Background job for processing medicine images into multiple sizes.

  This job is triggered after image upload and processes the original image
  into optimized sizes (600px, 200px) for different use cases.
  """

  use Oban.Worker, queue: :image_processing, max_attempts: 3

  require Logger
  alias Medpack.ImageProcessor
  alias Medpack.{BatchProcessing, ImageVariants}

  @doc """
  Performs the image processing job.

  Expects args with:
  - image_path: The path/key of the original image
  - medicine_id: The medicine ID to update (optional)
  - entry_id: The batch entry ID to update (optional)
  - context: Either "medicine" or "batch_entry"
  - photo_path: The specific photo path being processed (optional)
  - variant_size: The specific variant size being processed (optional)
  """
  def perform(%Oban.Job{
        args: %{
          "image_path" => image_path,
          "context" => context
        } = args
      }) do
    Logger.info("Starting image processing job for: #{image_path}")

    # Check if this is a new-style job with variant_size
    case Map.get(args, "variant_size") do
      nil ->
        # Legacy job - process all sizes
        case ImageProcessor.process_image_sizes(image_path) do
          {:ok, resized_paths} ->
            Logger.info("Image processing successful, updating database")
            update_database_with_resized_paths(context, args, resized_paths)

          {:error, reason} ->
            Logger.error("Image processing failed: #{reason}")
            {:error, reason}
        end

      variant_size ->
        # New-style job - process specific variant
        process_single_variant(context, args, variant_size)
    end
  end

  # Handle invalid job args
  def perform(%Oban.Job{args: args}) do
    Logger.error("Invalid ProcessImageSizesJob args: #{inspect(args)}")
    {:error, "Invalid job arguments"}
  end

  # Private functions

  defp process_single_variant("medicine", %{"medicine_id" => medicine_id, "photo_path" => photo_path, "variant_size" => variant_size}, _variant_size) do
    # Get the image variant record
    case ImageVariants.get_image_variant(medicine_id, photo_path, variant_size) do
      nil ->
        Logger.error("Image variant not found for medicine #{medicine_id}, photo #{photo_path}, size #{variant_size}")
        {:error, "Image variant not found"}

      image_variant ->
        # Mark as processing
        ImageVariants.update_processing_status(image_variant, "processing")

        # Process the specific variant
        case ImageProcessor.process_image_sizes(photo_path) do
          {:ok, resized_paths} ->
            # Get the specific variant path
            variant_path = Map.get(resized_paths, variant_size)

            if variant_path do
              # Update the variant record with the path and mark as completed
              case ImageVariants.update_variant_path(image_variant, variant_path) do
                {:ok, updated_variant} ->
                  ImageVariants.update_processing_status(updated_variant, "completed")
                  Logger.info("Successfully processed variant #{variant_size} for medicine #{medicine_id}, photo #{photo_path}")
                  {:ok, updated_variant}

                {:error, changeset} ->
                  ImageVariants.update_processing_status(image_variant, "failed", error: "Failed to update variant path: #{inspect(changeset.errors)}")
                  Logger.error("Failed to update variant path: #{inspect(changeset.errors)}")
                  {:error, "Failed to update variant path"}
              end
            else
              ImageVariants.update_processing_status(image_variant, "failed", error: "Variant path not found in processing result")
              Logger.error("Variant path not found in processing result for size #{variant_size}")
              {:error, "Variant path not found"}
            end

          {:error, reason} ->
            ImageVariants.update_processing_status(image_variant, "failed", error: reason)
            Logger.error("Image processing failed for variant #{variant_size}: #{reason}")
            {:error, reason}
        end
    end
  end

  defp process_single_variant(context, args, variant_size) do
    Logger.error("Unknown context for single variant processing: #{context}, args: #{inspect(args)}, variant_size: #{variant_size}")
    {:error, "Unknown processing context"}
  end

  defp update_database_with_resized_paths("medicine", %{"medicine_id" => medicine_id, "photo_path" => photo_path}, _resized_paths) do
    Logger.warning("Legacy image processing job detected for medicine #{medicine_id}, photo #{photo_path}. Please use the new image variants system.")
    {:ok, "Legacy processing completed - please migrate to new system"}
  end

  # Fallback for jobs without photo_path (backward compatibility)
  defp update_database_with_resized_paths("medicine", %{"medicine_id" => medicine_id, "image_path" => image_path}, _resized_paths) do
    Logger.warning("Legacy image processing job detected for medicine #{medicine_id}, image #{image_path}. Please use the new image variants system.")
    {:ok, "Legacy processing completed - please migrate to new system"}
  end

  defp update_database_with_resized_paths("batch_entry", %{"entry_id" => entry_id, "image_id" => image_id}, _resized_paths) do
    # For batch entries, we might want to store resized paths in the EntryImage record
    # or add a field to track processing status
    case BatchProcessing.get_entry(entry_id) do
      nil ->
        Logger.error("Batch entry not found: #{entry_id}")
        {:error, "Batch entry not found"}

      _entry ->
        # For now, just log success since batch entries will be processed into medicines later
        Logger.info("Batch entry #{entry_id} image #{image_id} processing complete")
        # We could store the resized paths in a temporary field or cache
        {:ok, "Batch entry image processed"}
    end
  end

  defp update_database_with_resized_paths(context, args, _resized_paths) do
    Logger.error("Unknown context for image processing: #{context}, args: #{inspect(args)}")
    {:error, "Unknown processing context"}
  end

end
