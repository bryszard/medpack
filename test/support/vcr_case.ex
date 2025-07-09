defmodule Medpack.VCRCase do
  @moduledoc """
  This module defines the setup for tests that use ExVCR for HTTP recordings.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use ExVCR.Mock, adapter: ExVCR.Adapter.Finch

      alias Medpack.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Medpack.DataCase
      import Medpack.Factory
      import Medpack.VCRCase
    end
  end

  setup tags do
    Medpack.DataCase.setup_sandbox(tags)

    # Ensure ExVCR uses the correct cassette directory
    ExVCR.Config.cassette_library_dir("test/fixtures/vcr_cassettes")

    # Set up test API key for OpenAI
    original_api_key = Application.get_env(:ex_openai, :api_key)
    Application.put_env(:ex_openai, :api_key, "sk-test-api-key")

    on_exit(fn ->
      if original_api_key do
        Application.put_env(:ex_openai, :api_key, original_api_key)
      else
        Application.delete_env(:ex_openai, :api_key)
      end
    end)

    :ok
  end

  @doc """
  Creates a test image file with given content for upload testing.
  """
  def create_test_image(content \\ <<255, 216, 255>>, filename \\ "test_image.jpg") do
    path = Path.join([System.tmp_dir(), filename])
    File.write!(path, content)

    on_exit(fn ->
      if File.exists?(path), do: File.rm!(path)
    end)

    path
  end

  @doc """
  Creates a realistic JPEG test image with minimal JPEG headers.
  """
  def create_realistic_test_image(filename \\ "realistic_test.jpg") do
    # Minimal JPEG file structure for testing
    jpeg_content = <<
      # JPEG SOI marker
      0xFF,
      0xD8,
      # APP0 marker
      0xFF,
      0xE0,
      0x00,
      0x10,
      0x4A,
      0x46,
      0x49,
      0x46,
      0x00,
      0x01,
      0x01,
      0x01,
      0x00,
      0x48,
      0x00,
      0x48,
      0x00,
      0x00,
      # SOF0 marker (simplified)
      0xFF,
      0xC0,
      0x00,
      0x11,
      0x08,
      0x00,
      0x01,
      0x00,
      0x01,
      0x01,
      0x01,
      0x11,
      0x00,
      0x02,
      0x11,
      0x01,
      0x03,
      0x11,
      0x01,
      # DHT marker (simplified)
      0xFF,
      0xC4,
      0x00,
      0x15,
      0x00,
      0x01,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x08,
      # SOS marker
      0xFF,
      0xDA,
      0x00,
      0x08,
      0x01,
      0x01,
      0x00,
      0x00,
      0x3F,
      0x00,
      # Image data (minimal)
      0xD2,
      0xCF,
      0x20,
      # EOI marker
      0xFF,
      0xD9
    >>

    create_test_image(jpeg_content, filename)
  end

  @doc """
  Helper function to get cassette path for a given test name.
  """
  def cassette_path(test_name) do
    Path.join(["test", "fixtures", "vcr_cassettes", "#{test_name}.json"])
  end

  @doc """
  Cleans up test files and directories.
  """
  def cleanup_test_files do
    Medpack.Factory.cleanup_test_files()
  end

  @doc """
  Creates a mock OpenAI response for successful medicine analysis.
  """
  def mock_successful_analysis_response do
    %{
      "id" => "chatcmpl-test123",
      "object" => "chat.completion",
      "created" => 1_699_999_999,
      "model" => "gpt-4-vision-preview",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" =>
              Jason.encode!(%{
                "name" => "Ibuprofen 200mg",
                "brand_name" => "Advil",
                "generic_name" => "Ibuprofen",
                "dosage_form" => "tablet",
                "active_ingredient" => "Ibuprofen",
                "strength_value" => 200.0,
                "strength_unit" => "mg",
                "container_type" => "bottle",
                "total_quantity" => 50.0,
                "quantity_unit" => "tablets",
                "manufacturer" => "Pfizer"
              })
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150
      }
    }
  end

  @doc """
  Creates a mock OpenAI response for failed analysis.
  """
  def mock_failed_analysis_response do
    %{
      "error" => %{
        "message" => "Unable to identify medicine clearly",
        "type" => "invalid_request_error",
        "code" => nil
      }
    }
  end

  @doc """
  Creates a mock OpenAI response for unclear image.
  """
  def mock_unclear_image_response do
    %{
      "id" => "chatcmpl-test456",
      "object" => "chat.completion",
      "created" => 1_699_999_999,
      "model" => "gpt-4-vision-preview",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" =>
              Jason.encode!(%{
                "error" => "Unable to identify medicine clearly"
              })
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 100,
        "completion_tokens" => 20,
        "total_tokens" => 120
      }
    }
  end
end
