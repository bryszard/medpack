defmodule Medpack.Jobs.ProcessImageSizesJob do
  @moduledoc """
  Background job for processing medicine images into multiple sizes.
  
  This job is triggered after image upload and processes the original image
  into optimized sizes (600px, 450px, 200px) for different use cases.
  """

  use Oban.Worker, queue: :image_processing, max_attempts: 3

  require Logger
  alias Medpack.ImageProcessor
  alias Medpack.{Medicines, BatchProcessing}

  @doc """
  Performs the image processing job.
  
  Expects args with:
  - image_path: The path/key of the original image
  - medicine_id: The medicine ID to update (optional)
  - entry_id: The batch entry ID to update (optional)
  - context: Either "medicine" or "batch_entry"
  """
  def perform(%Oban.Job{
        args: %{
          "image_path" => image_path,
          "context" => context
        } = args
      }) do
    Logger.info("Starting image processing job for: #{image_path}")

    case ImageProcessor.process_image_sizes(image_path) do
      {:ok, resized_paths} ->
        Logger.info("Image processing successful, updating database")
        update_database_with_resized_paths(context, args, resized_paths)

      {:error, reason} ->
        Logger.error("Image processing failed: #{reason}")
        {:error, reason}
    end
  end

  # Handle invalid job args
  def perform(%Oban.Job{args: args}) do
    Logger.error("Invalid ProcessImageSizesJob args: #{inspect(args)}")
    {:error, "Invalid job arguments"}
  end

  # Private functions

  defp update_database_with_resized_paths("medicine", %{"medicine_id" => medicine_id}, resized_paths) do
    case Medicines.get_medicine(medicine_id) do
      nil ->
        Logger.error("Medicine not found: #{medicine_id}")
        {:error, "Medicine not found"}

      medicine ->
        # Update the medicine's resized_photo_paths field
        case update_medicine_resized_paths(medicine, resized_paths) do
          {:ok, updated_medicine} ->
            Logger.info("Successfully updated medicine #{medicine_id} with resized image paths")
            {:ok, updated_medicine}

          {:error, changeset} ->
            Logger.error("Failed to update medicine #{medicine_id}: #{inspect(changeset.errors)}")
            {:error, "Failed to update medicine"}
        end
    end
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

  defp update_medicine_resized_paths(medicine, resized_paths) do
    # Get the original photo_paths
    original_photo_paths = medicine.photo_paths || []
    
    # Find which photo we're processing (this is a simplified approach)
    # In a more complex scenario, you might need to track which specific photo is being processed
    case original_photo_paths do
      [first_path | _] ->
        # For now, we'll update the resized_photo_paths for the first photo
        # In practice, you'd want to match the specific photo being processed
        resized_photo_paths = Map.put(medicine.resized_photo_paths || %{}, first_path, resized_paths)
        
        Medicines.update_medicine(medicine, %{resized_photo_paths: resized_photo_paths})
        
      [] ->
        Logger.warning("Medicine #{medicine.id} has no photo_paths to process")
        {:ok, medicine}
    end
  end
end