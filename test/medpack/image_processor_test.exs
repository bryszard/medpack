defmodule Medpack.ImageProcessorTest do
  use Medpack.DataCase
  alias Medpack.ImageProcessor

  describe "generate_resized_filename/2" do
    test "generates correct WebP filename for different sizes" do
      assert ImageProcessor.generate_resized_filename("image.jpg", "600") == "image_600.webp"
      assert ImageProcessor.generate_resized_filename("photo.png", "450") == "photo_450.webp"
      assert ImageProcessor.generate_resized_filename("test.jpeg", "200") == "test_200.webp"
    end

    test "returns original filename for original size" do
      assert ImageProcessor.generate_resized_filename("image.jpg", "original") == "image.jpg"
    end
  end

  describe "generate_resized_path/2" do
    test "generates correct S3 path for resized WebP images" do
      # Mock S3 storage
      Application.put_env(:medpack, :file_storage_backend, :s3)
      
      original_path = "medicines/image.jpg"
      assert ImageProcessor.generate_resized_path(original_path, "600") == "medicines/image_600.webp"
      
      # Reset to default
      Application.put_env(:medpack, :file_storage_backend, :local)
    end

    test "generates correct local path for resized WebP images" do
      original_path = "uploads/medicines/image.jpg"
      assert ImageProcessor.generate_resized_path(original_path, "450") == "uploads/medicines/image_450.webp"
    end

    test "returns original path for original size" do
      original_path = "medicines/image.jpg"
      assert ImageProcessor.generate_resized_path(original_path, "original") == original_path
    end
  end
end