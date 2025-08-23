defmodule Medpack.FileManagerWebPTest do
  use ExUnit.Case
  alias Medpack.FileManager

  describe "WebP content-type support" do
    test "recognizes WebP content type" do
      assert FileManager.get_content_type_locally("image.webp") == "image/webp"
      assert FileManager.get_content_type_locally("photo.WEBP") == "image/webp"
    end

    test "generates WebP paths for resized images" do
      original_url = FileManager.get_photo_url("uploads/medicines/image.jpg", size: "450")
      assert String.ends_with?(original_url, "_450.webp")
    end

    test "still serves original format for original size" do
      original_url = FileManager.get_photo_url("uploads/medicines/image.jpg", size: "original")
      assert String.ends_with?(original_url, ".jpg")
    end
  end
end