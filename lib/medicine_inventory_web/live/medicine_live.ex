defmodule MedicineInventoryWeb.MedicineLive do
  use MedicineInventoryWeb, :live_view

  alias MedicineInventory.{Medicines, Medicine}

  @impl true
  def mount(_params, _session, socket) do
    medicines = Medicines.list_medicines()
    changeset = Medicine.create_changeset()

    {:ok,
     socket
     |> assign(:medicines, medicines)
     |> assign(:form, to_form(changeset))
     |> assign(:search_query, "")
     |> assign(:show_form, false)
     |> assign(:uploaded_files, [])
     |> assign(:ai_processing, false)
     |> assign(:ai_results, nil)
     |> assign(:analyzing, false)
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 3,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"medicine" => medicine_params}, socket) do
    changeset =
      %Medicine{}
      |> Medicine.changeset(medicine_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"medicine" => medicine_params}, socket) do
    photo_paths = consume_uploaded_photos(socket)
    medicine_params = Map.put(medicine_params, "photo_paths", photo_paths)

    case Medicines.create_medicine(medicine_params) do
      {:ok, medicine} ->
        # Broadcast to all connected clients
        Phoenix.PubSub.broadcast(
          MedicineInventory.PubSub,
          "medicines",
          {:medicine_created, medicine}
        )

        medicines = Medicines.list_medicines()
        changeset = Medicine.create_changeset()

        {:noreply,
         socket
         |> assign(:medicines, medicines)
         |> assign(:form, to_form(changeset))
         |> assign(:show_form, false)
         |> assign(:ai_results, nil)
         |> put_flash(:info, "Medicine added successfully!")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("search", %{"query" => query}, socket) do
    medicines =
      if query == "" do
        Medicines.list_medicines()
      else
        Medicines.search_medicines(query)
      end

    {:noreply,
     socket
     |> assign(:medicines, medicines)
     |> assign(:search_query, query)}
  end

  def handle_event("toggle_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, not socket.assigns.show_form)
     |> assign(:ai_results, nil)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  def handle_event("analyze_photos", _params, socket) do
    # Check if we have uploaded entries
    entries = socket.assigns.uploads.photos.entries

    if entries != [] do
      # Get the first uploaded entry and access its temporary file path
      first_entry = List.first(entries)

      # Access the temporary file path directly from the upload entry
      case get_upload_temp_path(socket, first_entry) do
        {:ok, temp_path} ->
          {:noreply,
           socket
           |> assign(:analyzing, true)
           |> start_async(:analyze_medicine_photos, fn -> analyze_medicine_photos(temp_path) end)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Error accessing photo: #{reason}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please upload at least one photo first")}
    end
  end

  def handle_event("apply_ai_suggestions", _params, socket) do
    if socket.assigns.ai_results do
      changeset = Medicine.changeset(%Medicine{}, socket.assigns.ai_results)

      {:noreply,
       socket
       |> assign(:form, to_form(changeset))
       |> put_flash(:info, "AI suggestions applied! Please review and adjust as needed.")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:analyze_medicine_photos, {:ok, ai_results}, socket) do
    {:noreply,
     socket
     |> assign(:analyzing, false)
     |> assign(:ai_results, ai_results)
     |> put_flash(:info, "AI analysis complete! Review the suggestions below.")}
  end

  def handle_async(:analyze_medicine_photos, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:analyzing, false)
     |> put_flash(:error, "AI analysis failed. Please try again or fill in manually.")}
  end

  @impl true
  def handle_info({:medicine_created, _medicine}, socket) do
    medicines = Medicines.list_medicines()
    {:noreply, assign(socket, medicines: medicines)}
  end


            _ ->
              {:error, "File upload not complete"}
          end
        end

      _ ->
        {:error, "Invalid upload entry"}
    end
  rescue
    error ->
      # Fallback: use the socket's upload system to access the file
      try do
        # Try to access via the upload entry's internal path
        upload_path =
          Path.join([
            System.tmp_dir(),
            "phoenix_uploads",
            socket.id,
            entry.uuid
          ])

        if File.exists?(upload_path) do
          {:ok, upload_path}
        else
          {:error, "Upload file not found: #{inspect(error)}"}
        end
      rescue
        _ -> {:error, "Cannot access upload file"}
      end
  end

  defp analyze_medicine_photos(file_path) do
    # Read the uploaded file and convert to base64
    case File.read(file_path) do
      {:ok, file_data} ->
        base64_image = Base.encode64(file_data)
        call_openai_vision_api(base64_image)

      {:error, reason} ->
        IO.inspect({:file_read_error, reason, file_path}, label: "File read error")
        simulate_ai_analysis()
    end
  end

  defp call_openai_vision_api(base64_image) do
    # You'll need to set your OpenAI API key in your environment
    api_key = System.get_env("OPENAI_API_KEY")

    if api_key do
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      # Define the JSON schema for structured extraction
      json_schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{
            "type" => "string",
            "description" =>
              "The complete medicine name including brand/generic name and strength"
          },
          "brand_name" => %{
            "type" => "string",
            "description" => "Brand name if visible (e.g., Tylenol, Advil)"
          },
          "generic_name" => %{
            "type" => "string",
            "description" => "Generic/active ingredient name (e.g., Acetaminophen, Ibuprofen)"
          },
          "dosage_form" => %{
            "type" => "string",
            "enum" => [
              "tablet",
              "capsule",
              "syrup",
              "suspension",
              "solution",
              "cream",
              "ointment",
              "gel",
              "lotion",
              "drops",
              "injection",
              "inhaler",
              "spray",
              "patch",
              "suppository"
            ],
            "description" => "Form of the medicine"
          },
          "active_ingredient" => %{
            "type" => "string",
            "description" => "Primary active ingredient"
          },
          "strength_value" => %{
            "type" => "number",
            "description" => "Numeric strength value (e.g., 500 for 500mg)"
          },
          "strength_unit" => %{
            "type" => "string",
            "description" => "Unit of strength (mg, g, ml, mcg, IU, etc.)"
          },
          "strength_denominator_value" => %{
            "type" => "number",
            "description" => "Denominator value for ratios like mg/ml (e.g., 5 for mg/5ml)"
          },
          "strength_denominator_unit" => %{
            "type" => "string",
            "description" => "Denominator unit for ratios (ml, g, tablet, etc.)"
          },
          "container_type" => %{
            "type" => "string",
            "enum" => [
              "bottle",
              "box",
              "tube",
              "vial",
              "inhaler",
              "blister_pack",
              "sachet",
              "ampoule"
            ],
            "description" => "Type of container/packaging"
          },
          "total_quantity" => %{
            "type" => "number",
            "description" => "Total quantity in container if visible"
          },
          "quantity_unit" => %{
            "type" => "string",
            "description" => "Unit for quantity (tablets, capsules, ml, g, doses, etc.)"
          },
          "expiration_date" => %{
            "type" => "string",
            "pattern" => "^\\d{4}-\\d{2}-\\d{2}$",
            "description" => "Expiration date in YYYY-MM-DD format if visible"
          },
          "lot_number" => %{
            "type" => "string",
            "description" => "Lot or batch number if visible"
          },
          "manufacturer" => %{
            "type" => "string",
            "description" => "Manufacturer name if visible"
          },
          "indication" => %{
            "type" => "string",
            "description" => "What the medicine is used for if indicated on packaging"
          },
          "ndc_code" => %{
            "type" => "string",
            "description" => "NDC (National Drug Code) if visible"
          }
        },
        "required" => ["name"],
        "additionalProperties" => false
      }

      body = %{
        "model" => "gpt-4o",
        "messages" => [
          %{
            "role" => "system",
            "content" => """
            You are a pharmaceutical expert AI that analyzes medicine photos to extract structured data. 
            Extract all visible information from medicine packaging/labels with high accuracy.

            Focus on:
            - Medicine names (brand and generic)
            - Dosage forms (tablet, capsule, liquid, etc.)
            - Strength/concentration (mg, ml, etc.)
            - Container information
            - Expiration dates
            - Lot numbers
            - Manufacturer details

            Only extract information that is clearly visible. Use null for unclear/missing data.
            Return valid JSON matching the provided schema exactly.
            """
          },
          %{
            "role" => "user",
            "content" => [
              %{
                "type" => "text",
                "text" =>
                  "Please analyze this medicine image and extract all visible information according to the JSON schema. Be as accurate and complete as possible."
              },
              %{
                "type" => "image_url",
                "image_url" => %{
                  "url" => "data:image/jpeg;base64,#{base64_image}",
                  "detail" => "high"
                }
              }
            ]
          }
        ],
        "response_format" => %{
          "type" => "json_schema",
          "json_schema" => %{
            "name" => "medicine_extraction",
            "schema" => json_schema,
            "strict" => true
          }
        },
        "max_tokens" => 1000,
        "temperature" => 0.1
      }

      case Req.post("https://api.openai.com/v1/chat/completions",
             headers: headers,
             json: body
           ) do
        {:ok, %{status: 200, body: response}} ->
          content = get_in(response, ["choices", Access.at(0), "message", "content"])
          parse_ai_response(content)

        {:ok, %{status: status, body: error_body}} ->
          IO.inspect({:openai_error, status, error_body}, label: "OpenAI API Error")
          simulate_ai_analysis()

        {:error, error} ->
          IO.inspect({:request_error, error}, label: "Request Error")
          simulate_ai_analysis()
      end
    else
      # Fallback: return demo data if no API key
      simulate_ai_analysis()
    end
  end

  defp parse_ai_response(content) when is_binary(content) do
    try do
      case Jason.decode(content) do
        {:ok, data} when is_map(data) ->
          # Clean up the data and ensure proper types
          clean_ai_data(data)

        {:error, _} ->
          simulate_ai_analysis()
      end
    rescue
      _ -> simulate_ai_analysis()
    end
  end

  defp parse_ai_response(_), do: simulate_ai_analysis()

  defp clean_ai_data(data) when is_map(data) do
    # Convert string numbers to actual numbers and clean up the data
    data
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      cleaned_value =
        case {key, value} do
          {key, value}
          when key in ["strength_value", "strength_denominator_value", "total_quantity"] and
                 is_binary(value) ->
            case Float.parse(value) do
              {num, _} -> num
              :error -> nil
            end

          {_key, value} when is_binary(value) and value == "" ->
            nil

          {_key, value} ->
            value
        end

      if cleaned_value != nil do
        Map.put(acc, key, cleaned_value)
      else
        acc
      end
    end)
    # Default remaining = total
    |> Map.put("remaining_quantity", Map.get(data, "total_quantity"))
  end

  defp simulate_ai_analysis do
    # Enhanced simulation with realistic demo data
    %{
      "name" => "Demo Medicine Analysis - Ibuprofen 200mg",
      "brand_name" => "Advil",
      "generic_name" => "Ibuprofen",
      "dosage_form" => "tablet",
      "active_ingredient" => "Ibuprofen",
      "strength_value" => 200.0,
      "strength_unit" => "mg",
      "container_type" => "bottle",
      "total_quantity" => 100.0,
      "remaining_quantity" => 100.0,
      "quantity_unit" => "tablets",
      "manufacturer" => "Pfizer",
      "indication" =>
        "Pain relief, fever reduction - AI analysis requires OpenAI API key for real data"
    }
  end

  defp consume_uploaded_photos(socket) do
    consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
      # Create a unique filename using the original name and timestamp
      timestamp = System.system_time(:millisecond)
      extension = Path.extname(entry.client_name)
      filename = "#{timestamp}_#{Path.basename(entry.client_name, extension)}#{extension}"

      dest = Path.join([:code.priv_dir(:medicine_inventory), "static", "uploads", filename])
      File.cp!(path, dest)
      {:ok, filename}
    end)
  end
end
