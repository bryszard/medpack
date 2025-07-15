defmodule Medpack.AI.ImageAnalyzer do
  @moduledoc """
  Handles AI-powered image analysis for medicine identification using OpenAI's Vision API.

  All images are converted to base64 before sending to OpenAI, including those stored in S3/Tigris.
  This ensures compatibility with private or cluster-internal storage that may not be accessible
  to external services.
  """

  require Logger

  # Retry configuration
  @max_retries 3
  @base_delay_ms 1000
  @max_delay_ms 10000
  @timeout_ms 60000

  @doc """
  Analyzes a medicine photo using OpenAI's Vision API.

  This is a convenience wrapper around `analyze_medicine_photos/1` for single images.
  Returns a map with extracted medicine information or an error.
  """
  def analyze_medicine_photo(image_path_or_url) when is_binary(image_path_or_url) do
    analyze_medicine_photos([image_path_or_url])
  end

  @doc """
  Analyzes medicine photos using OpenAI's Vision API.

  Accepts either a single image or multiple images. When multiple images are provided,
  they are analyzed together as a single medicine product for more comprehensive results.
  Returns a map with extracted medicine information or an error.
  """
  def analyze_medicine_photos(image_paths_or_urls) when is_list(image_paths_or_urls) do
    case validate_and_prepare_images(image_paths_or_urls) do
      {:ok, base64_images} ->
        perform_analysis(base64_images)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_image_for_analysis(image_path_or_url) do
    if String.starts_with?(image_path_or_url, "http") do
      # S3/Tigris URL - download and encode to base64 (never send URLs to OpenAI)
      download_and_encode_image(image_path_or_url)
    else
      # Local file path - encode directly to base64
      case File.exists?(image_path_or_url) do
        true ->
          encode_image(image_path_or_url)

        false ->
          {:error, :file_not_found}
      end
    end
  end

  defp download_and_encode_image(url) do
    try do
      case Req.get(url, receive_timeout: 30_000) do
        {:ok, %{status: 200, body: image_data}} ->
          base64_image = Base.encode64(image_data)
          {:ok, base64_image}

        {:ok, %{status: status}} ->
          Logger.error("Failed to download image from S3: HTTP #{status}")
          {:error, {:download_failed, status}}

        {:error, error} ->
          Logger.error("Failed to download image from S3: #{inspect(error)}")
          {:error, {:download_error, error}}
      end
    rescue
      e ->
        Logger.error("Exception while downloading image from S3: #{inspect(e)}")
        {:error, {:download_exception, e}}
    end
  end

  defp validate_and_prepare_images(image_paths_or_urls) do
    if length(image_paths_or_urls) == 0 do
      {:error, :no_images_provided}
    else
      case Enum.reduce_while(image_paths_or_urls, [], fn path_or_url, acc ->
             case prepare_image_for_analysis(path_or_url) do
               {:ok, base64_image} -> {:cont, [base64_image | acc]}
               {:error, :file_not_found} -> {:halt, {:error, {:file_not_found, path_or_url}}}
               {:error, reason} -> {:halt, {:error, reason}}
             end
           end) do
        {:error, reason} -> {:error, reason}
        base64_images -> {:ok, Enum.reverse(base64_images)}
      end
    end
  end

  defp perform_analysis(base64_images) do
    try do
      case call_openai_vision(base64_images) do
        {:ok, analysis_result} ->
          parse_analysis_result(analysis_result)

        {:error, reason} ->
          Logger.error("OpenAI API call failed: #{inspect(reason)}")
          {:error, :api_call_failed}
      end
    rescue
      e ->
        Logger.error("Multi-analysis failed with exception: #{inspect(e)}")
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

  defp call_openai_with_retry(request_body) do
    api_key = System.get_env("OPENAI_API_KEY")

    do_retry(
      fn ->
        Req.post("https://api.openai.com/v1/chat/completions",
          headers: [
            {"Authorization", "Bearer #{api_key}"},
            {"Content-Type", "application/json"}
          ],
          json: request_body,
          receive_timeout: @timeout_ms
        )
      end,
      @max_retries
    )
  end

  defp do_retry(fun, retries_left, attempt \\ 1)

  defp do_retry(_fun, 0, attempt) do
    Logger.error(
      "All #{@max_retries} retry attempts failed for OpenAI API call (attempt #{attempt})"
    )

    {:error, :max_retries_exceeded}
  end

  defp do_retry(fun, retries_left, attempt) do
    case fun.() do
      {:ok, %{status: 200, body: response}} ->
        content = get_in(response, ["choices", Access.at(0), "message", "content"])
        {:ok, content}

      {:ok, %{status: status, body: error_body}} when status in [429, 500, 502, 503, 504] ->
        # Retryable errors: rate limit, server errors
        Logger.warning(
          "OpenAI API retryable error #{status} (attempt #{attempt}/#{@max_retries}): #{inspect(error_body)}"
        )

        if retries_left > 0 do
          delay = calculate_delay(attempt)
          Logger.info("Retrying OpenAI API call in #{delay}ms...")
          Process.sleep(delay)
          do_retry(fun, retries_left - 1, attempt + 1)
        else
          Logger.error("OpenAI API error #{status}: #{inspect(error_body)}")
          {:error, error_body}
        end

      {:ok, %{status: status, body: error_body}} ->
        # Non-retryable errors: 400, 401, 403, etc.
        Logger.error("OpenAI API non-retryable error #{status}: #{inspect(error_body)}")
        {:error, error_body}

      {:error, %Req.TransportError{reason: :timeout}} ->
        Logger.warning("OpenAI API timeout (attempt #{attempt}/#{@max_retries})")

        if retries_left > 0 do
          delay = calculate_delay(attempt)
          Logger.info("Retrying OpenAI API call after timeout in #{delay}ms...")
          Process.sleep(delay)
          do_retry(fun, retries_left - 1, attempt + 1)
        else
          Logger.error("OpenAI API timeout after #{@max_retries} attempts")
          {:error, :timeout}
        end

      {:error, error} ->
        Logger.warning(
          "OpenAI API transport error (attempt #{attempt}/#{@max_retries}): #{inspect(error)}"
        )

        if retries_left > 0 do
          delay = calculate_delay(attempt)
          Logger.info("Retrying OpenAI API call after transport error in #{delay}ms...")
          Process.sleep(delay)
          do_retry(fun, retries_left - 1, attempt + 1)
        else
          Logger.error(
            "OpenAI API transport error after #{@max_retries} attempts: #{inspect(error)}"
          )

          {:error, error}
        end
    end
  end

  defp calculate_delay(attempt) do
    # Exponential backoff with jitter
    base_delay = @base_delay_ms * :math.pow(2, attempt - 1)
    # Add up to 1 second of jitter
    jitter = :rand.uniform(1000)
    delay = round(base_delay + jitter)
    min(delay, @max_delay_ms)
  end

  defp call_openai_vision(base64_images) do
    # Build content array with text prompt and multiple images (all base64)
    content = [
      %{
        type: "text",
        text: build_prompt()
      }
    ]

    # Add each base64 image to the content
    image_content =
      Enum.map(base64_images, fn base64_image ->
        %{
          type: "image_url",
          image_url: %{
            url: "data:image/jpeg;base64,#{base64_image}"
          }
        }
      end)

    messages = [
      %{
        role: "user",
        content: content ++ image_content
      }
    ]

    request_body = %{
      model: "gpt-4o",
      messages: messages,
      max_tokens: 1500,
      temperature: 0.1
    }

    call_openai_with_retry(request_body)
  end

  defp build_prompt do
    """
    You are a medical expert specializing in pharmaceutical identification. I'm providing you with one or multiple photos of the same medicine product. Please analyze all the images together to extract comprehensive information about this medicine.

    Look across all images to gather information from different angles, sides, or views of the medicine package. Use information from all photos to provide the most complete and accurate analysis possible.

    Extract the following information in JSON format:

    {
      "name": "Full product name as shown on the package",
      "brand_name": "Brand name (e.g., Tylenol, Advil)",
      "generic_name": "Generic/active ingredient name (e.g., Acetaminophen, Ibuprofen)",
      "dosage_form": "Form of medication - MUST be one of: tablet, capsule, syrup, suspension, solution, cream, ointment, gel, lotion, drops, injection, inhaler, spray, patch, suppository",
      "active_ingredient": "Primary active ingredient",
      "strength_value": "Numeric strength value (e.g., 500.0)",
      "strength_unit": "Unit of strength (mg, ml, g, etc.)",
      "container_type": "Type of container - MUST be one of: bottle, box, tube, vial, inhaler, blister_pack, sachet, ampoule",
      "total_quantity": "Total quantity in container (numeric)",
      "remaining_quantity": "Remaining quantity in container (numeric)",
      "quantity_unit": "Unit for quantities (tablets, ml, capsules, etc.)",
      "manufacturer": "Manufacturer name if visible",
      "lot_number": "Lot number if visible",
      "expiration_date": "Expiration date if visible (YYYY-MM-DD format) - MUST be a valid future date, do not include if date is unclear, past, or cannot be clearly read"
    }

    Guidelines:
    - Analyze ALL provided images together to get the most complete information
    - Only include information that is clearly visible in at least one of the images
    - Omit fields that cannot be determined from any of the images (don't include them in the JSON)
    - Be conservative with estimates but use all available visual information
    - For strength_value, use only the numeric part (e.g., 500.0 not "500mg")
    - For dosage_form, use EXACTLY one of these values: tablet, capsule, syrup, suspension, solution, cream, ointment, gel, lotion, drops, injection, inhaler, spray, patch, suppository
    - For container_type, use EXACTLY one of these values: bottle, box, tube, vial, inhaler, blister_pack, sachet, ampoule
    - Identify dosage form based on visual cues across all images
    - Translate foreign terms to English (e.g., "Lösung" in small bottles → "drops", "Tabletten" → "tablet", "Flasche" → "bottle")
    - Extract any visible information from any of the images, even if incomplete
    - DO NOT try to estimate remaining quantity - this will be managed manually by the user
    - If you cannot identify ANY medicine information clearly from any image, return {"error": "Unable to identify medicine clearly"}
    - For total_quantity, if it's not indicated, give your best guess
    - For remaining_quantity, give your best guess

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
      "expiration_date"
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
