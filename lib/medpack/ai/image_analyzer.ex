defmodule Medpack.AI.ImageAnalyzer do
  @moduledoc """
  Handles AI-powered image analysis for medicine identification using OpenAI's Vision API.
  """

  require Logger

  # Retry configuration
  @max_retries 3
  @base_delay_ms 1000
  @max_delay_ms 10000
  @timeout_ms 60000

  @doc """
  Analyzes a medicine photo using OpenAI's Vision API.

  Returns a map with extracted medicine information or an error.
  """
  def analyze_medicine_photo(image_path_or_url) when is_binary(image_path_or_url) do
    if String.starts_with?(image_path_or_url, "http") do
      # S3 URL - use directly with OpenAI
      perform_url_analysis(image_path_or_url)
    else
      # Local file path
      case File.exists?(image_path_or_url) do
        true ->
          perform_analysis(image_path_or_url)

        false ->
          {:error, :file_not_found}
      end
    end
  end

  @doc """
  Analyzes multiple medicine photos using OpenAI's Vision API in a single call.

  Returns a map with extracted medicine information or an error.
  """
  def analyze_medicine_photos(image_paths_or_urls) when is_list(image_paths_or_urls) do
    case validate_and_prepare_images(image_paths_or_urls) do
      {:ok, image_data} ->
        perform_multi_analysis_mixed(image_data)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_and_prepare_images(image_paths_or_urls) do
    if length(image_paths_or_urls) == 0 do
      {:error, :no_images_provided}
    else
      case Enum.reduce_while(image_paths_or_urls, [], fn path_or_url, acc ->
             if String.starts_with?(path_or_url, "http") do
               # S3 URL - use directly
               {:cont, [{:url, path_or_url} | acc]}
             else
               # Local file path - encode
               case File.exists?(path_or_url) do
                 true ->
                   case encode_image(path_or_url) do
                     {:ok, encoded} -> {:cont, [{:encoded, encoded} | acc]}
                     {:error, reason} -> {:halt, {:error, reason}}
                   end

                 false ->
                   {:halt, {:error, {:file_not_found, path_or_url}}}
               end
             end
           end) do
        {:error, reason} -> {:error, reason}
        image_data -> {:ok, Enum.reverse(image_data)}
      end
    end
  end

  defp validate_and_encode_images(image_paths) do
    if length(image_paths) == 0 do
      {:error, :no_images_provided}
    else
      case Enum.reduce_while(image_paths, [], fn path, acc ->
             case File.exists?(path) do
               true ->
                 case encode_image(path) do
                   {:ok, encoded} -> {:cont, [encoded | acc]}
                   {:error, reason} -> {:halt, {:error, reason}}
                 end

               false ->
                 {:halt, {:error, {:file_not_found, path}}}
             end
           end) do
        {:error, reason} -> {:error, reason}
        encoded_images -> {:ok, Enum.reverse(encoded_images)}
      end
    end
  end

  defp perform_multi_analysis_mixed(image_data) do
    try do
      case call_openai_vision_multi_mixed(image_data) do
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

  defp perform_multi_analysis(encoded_images) do
    try do
      case call_openai_vision_multi(encoded_images) do
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

  defp perform_url_analysis(image_url) do
    try do
      case call_openai_vision_url(image_url) do
        {:ok, analysis_result} ->
          parse_analysis_result(analysis_result)

        {:error, reason} ->
          Logger.error("OpenAI API call failed: #{inspect(reason)}")
          {:error, :api_call_failed}
      end
    rescue
      e ->
        Logger.error("URL analysis failed with exception: #{inspect(e)}")
        {:error, :analysis_exception}
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

  defp call_openai_vision_multi_mixed(image_data) do
    # Build content array with text prompt and multiple images (mixed URLs and base64)
    content = [
      %{
        type: "text",
        text: build_multi_analysis_prompt()
      }
    ]

    # Add each image to the content, handling both URLs and base64 encoded images
    image_content =
      Enum.map(image_data, fn
        {:url, url} ->
          %{
            type: "image_url",
            image_url: %{
              url: url
            }
          }

        {:encoded, base64_image} ->
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

  defp call_openai_vision_multi(encoded_images) do
    # Build content array with text prompt and multiple images
    content = [
      %{
        type: "text",
        text: build_multi_analysis_prompt()
      }
    ]

    # Add each image to the content
    image_content =
      Enum.map(encoded_images, fn base64_image ->
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

  defp call_openai_vision_url(image_url) do
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
              url: image_url
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

    call_openai_with_retry(request_body)
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

    call_openai_with_retry(request_body)
  end

  defp build_multi_analysis_prompt do
    """
    You are a medical expert specializing in pharmaceutical identification. I'm providing you with multiple photos of the same medicine product. Please analyze all the images together to extract comprehensive information about this medicine.

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

    Return only the JSON object, no additional text.
    """
  end

  defp build_analysis_prompt do
    """
    You are a medical expert specializing in pharmaceutical identification. Analyze this medicine photo and extract the following information in JSON format:

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
      "quantity_unit": "Unit for quantities (tablets, ml, capsules, etc.)",
      "manufacturer": "Manufacturer name if visible",
      "lot_number": "Lot number if visible",
      "expiration_date": "Expiration date if visible (YYYY-MM-DD format) - MUST be a valid future date, do not include if date is unclear, past, or cannot be clearly read"
    }

    Guidelines:
    - Only include information that is clearly visible in the image
    - Omit fields that cannot be determined (don't include them in the JSON)
    - Be conservative with estimates
    - For strength_value, use only the numeric part (e.g., 500.0 not "500mg")
    - For dosage_form, use EXACTLY one of these values: tablet, capsule, syrup, suspension, solution, cream, ointment, gel, lotion, drops, injection, inhaler, spray, patch, suppository
    - For container_type, use EXACTLY one of these values: bottle, box, tube, vial, inhaler, blister_pack, sachet, ampoule
    - Identify dosage form based on visual cues: small bottles with droppers/caps = "drops", larger bottles with syrup = "syrup", pill bottles = "tablet" or "capsule"
    - Translate foreign terms to English (e.g., "Lösung" in small bottles → "drops", "Tabletten" → "tablet", "Flasche" → "bottle")
    - Extract any visible information, even if incomplete
    - DO NOT try to estimate remaining quantity - this will be managed manually by the user
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
    numeric_fields = ["strength_value", "total_quantity"]

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
