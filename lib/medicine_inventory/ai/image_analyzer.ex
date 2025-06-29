defmodule MedicineInventory.AI.ImageAnalyzer do
  @moduledoc """
  Handles AI-powered image analysis for medicine identification using OpenAI's Vision API.
  """

  require Logger

  @doc """
  Analyzes a medicine photo using OpenAI's Vision API.

  Returns a map with extracted medicine information or an error.
  """
  def analyze_medicine_photo(image_path) when is_binary(image_path) do
    case File.exists?(image_path) do
      true ->
        perform_analysis(image_path)

      false ->
        {:error, :file_not_found}
    end
  end

  defp perform_analysis(image_path) do
    try do
      # Read and encode the image
      case encode_image(image_path) do
        {:ok, base64_image} ->
          # Call OpenAI Vision API
          case call_openai_vision(base64_image) do
            {:ok, analysis_result} ->
              parse_analysis_result(analysis_result)

            {:error, reason} ->
              Logger.error("OpenAI API call failed: #{inspect(reason)}")
              {:error, :api_call_failed}
          end

        {:error, reason} ->
          Logger.error("Image encoding failed: #{inspect(reason)}")
          {:error, :image_encoding_failed}
      end
    rescue
      e ->
        Logger.error("Analysis failed with exception: #{inspect(e)}")
        {:error, :analysis_exception}
    end
  end

  defp encode_image(image_path) do
    case File.read(image_path) do
      {:ok, image_data} ->
        base64_image = Base.encode64(image_data)
        {:ok, base64_image}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_openai_vision(base64_image) do
    # Get file extension for proper MIME type
    # Default, could be improved to detect actual type
    content_type = "image/jpeg"

    messages = [
      %{
        role: "user",
        content: [
          %{
            type: "text",
            text: build_analysis_prompt()
          },
          %{
            type: "image_url",
            image_url: %{
              url: "data:#{content_type};base64,#{base64_image}"
            }
          }
        ]
      }
    ]

    request_body = %{
      model: "gpt-4o",
      messages: messages,
      max_tokens: 1000,
      temperature: 0.1
    }

    # Use Req instead of ExOpenAI to avoid JSON serialization issues
    api_key = System.get_env("OPENAI_API_KEY")

    case Req.post("https://api.openai.com/v1/chat/completions",
           headers: [
             {"Authorization", "Bearer #{api_key}"},
             {"Content-Type", "application/json"}
           ],
           json: request_body
         ) do
      {:ok, %{status: 200, body: response}} ->
        content = get_in(response, ["choices", Access.at(0), "message", "content"])
        {:ok, content}

      {:ok, %{status: status, body: error_body}} ->
        Logger.error("OpenAI API error #{status}: #{inspect(error_body)}")
        {:error, error_body}

      {:error, error} ->
        Logger.error("HTTP request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp build_analysis_prompt do
    """
    You are a medical expert specializing in pharmaceutical identification. Analyze this medicine photo and extract the following information in JSON format:

    {
      "name": "Full product name as shown on the package",
      "brand_name": "Brand name (e.g., Tylenol, Advil)",
      "generic_name": "Generic/active ingredient name (e.g., Acetaminophen, Ibuprofen)",
      "dosage_form": "Form of medication (tablet, capsule, syrup, cream, etc.)",
      "active_ingredient": "Primary active ingredient",
      "strength_value": "Numeric strength value (e.g., 500.0)",
      "strength_unit": "Unit of strength (mg, ml, g, etc.)",
      "container_type": "Type of container (bottle, box, tube, etc.)",
      "total_quantity": "Total quantity in container (numeric)",
      "remaining_quantity": "Estimated remaining quantity (numeric, same as total if unopened)",
      "quantity_unit": "Unit for quantities (tablets, ml, capsules, etc.)",
      "manufacturer": "Manufacturer name if visible",
      "lot_number": "Lot number if visible",
      "expiration_date": "Expiration date if visible (YYYY-MM-DD format)",
      "ndc_code": "NDC code if visible"
    }

    Guidelines:
    - Only include information that is clearly visible in the image
    - Omit fields that cannot be determined (don't include them in the JSON)
    - Be conservative with estimates
    - For strength_value, use only the numeric part (e.g., 500.0 not "500mg")
    - For dosage_form, use lowercase (tablet, capsule, syrup, etc.)
    - For container_type, use lowercase (bottle, box, tube, etc.)
    - Extract any visible information, even if incomplete
    - If you cannot identify ANY medicine information clearly, return {"error": "Unable to identify medicine clearly"}

    Return only the JSON object, no additional text.
    """
  end

  defp parse_analysis_result(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"error" => error_message}} ->
        {:error, error_message}

      {:ok, medicine_data} when is_map(medicine_data) ->
        case validate_medicine_data(medicine_data) do
          {:ok, validated_data} -> {:ok, validated_data}
          {:error, reason} -> {:error, reason}
        end

      {:error, _json_error} ->
        # Try to extract JSON from the content if it's wrapped in other text
        case extract_json_from_text(content) do
          {:ok, medicine_data} ->
            case validate_medicine_data(medicine_data) do
              {:ok, validated_data} -> {:ok, validated_data}
              {:error, reason} -> {:error, reason}
            end

          {:error, _} ->
            {:error, :invalid_response_format}
        end
    end
  end

  defp extract_json_from_text(text) do
    # Try to find JSON object in the text
    case Regex.run(~r/\{.*\}/s, text) do
      [json_string] ->
        Jason.decode(json_string)

      _ ->
        {:error, :no_json_found}
    end
  end

  defp validate_medicine_data(data) when is_map(data) do
    # Since we're extracting from images, we don't require any specific fields
    # Any extracted information is valuable, even if incomplete

    # Convert numeric strings to proper types and sanitize data
    validated_data =
      data
      |> convert_numeric_fields()
      |> sanitize_data()

    # Check if we have at least some useful information
    case map_size(validated_data) do
      0 ->
        {:error, "No useful information could be extracted from the image"}

      _ ->
        {:ok, validated_data}
    end
  end

  defp convert_numeric_fields(data) do
    numeric_fields = ["strength_value", "total_quantity", "remaining_quantity"]

    Enum.reduce(numeric_fields, data, fn field, acc ->
      case Map.get(acc, field) do
        value when is_binary(value) ->
          case Float.parse(value) do
            {float_val, _} -> Map.put(acc, field, float_val)
            :error -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp sanitize_data(data) do
    data
    |> Map.take([
      "name",
      "brand_name",
      "generic_name",
      "dosage_form",
      "active_ingredient",
      "strength_value",
      "strength_unit",
      "container_type",
      "total_quantity",
      "remaining_quantity",
      "quantity_unit",
      "manufacturer",
      "lot_number",
      "expiration_date",
      "ndc_code"
    ])
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case value do
        nil -> acc
        "" -> acc
        _ -> Map.put(acc, key, value)
      end
    end)
  end
end
