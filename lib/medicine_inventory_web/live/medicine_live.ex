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
    # Store the first photo as the main photo_path for backwards compatibility
    main_photo = List.first(photo_paths)
    medicine_params = Map.put(medicine_params, "photo_path", main_photo)

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

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
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
    if socket.assigns.uploads.photos.entries != [] do
      {:noreply,
       socket
       |> assign(:ai_processing, true)
       |> start_async(:analyze_medicine_photos, fn -> analyze_medicine_photos(socket) end)}
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
     |> assign(:ai_processing, false)
     |> assign(:ai_results, ai_results)
     |> put_flash(:info, "AI analysis complete! Review the suggestions below.")}
  end

  def handle_async(:analyze_medicine_photos, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:ai_processing, false)
     |> put_flash(:error, "AI analysis failed. Please try again or fill in manually.")}
  end

  @impl true
  def handle_info({:medicine_created, _medicine}, socket) do
    medicines = Medicines.list_medicines()
    {:noreply, assign(socket, medicines: medicines)}
  end

  defp analyze_medicine_photos(socket) do
    # Get the first uploaded photo for analysis
    first_entry = List.first(socket.assigns.uploads.photos.entries)

    if first_entry do
      # Get the temporary file path from the upload entry
      temp_path = Phoenix.LiveView.Upload.path(socket.assigns.uploads.photos, first_entry)

      if temp_path && File.exists?(temp_path) do
        image_data = File.read!(temp_path)
        base64_image = Base.encode64(image_data)

        # Call OpenAI GPT-4 Vision API
        call_openai_vision_api(base64_image)
      else
        %{}
      end
    else
      %{}
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

      body = %{
        "model" => "gpt-4-vision-preview",
        "messages" => [
          %{
            "role" => "user",
            "content" => [
              %{
                "type" => "text",
                "text" => """
                Please analyze this medicine image and extract the following information in JSON format:
                - name: The medicine name and dosage (e.g., "Ibuprofen 200mg")
                - type: The form of medicine (e.g., "Tablet", "Capsule", "Liquid", "Cream")
                - quantity: Number of pills/doses if visible
                - expiration_date: Expiration date in YYYY-MM-DD format if visible
                - notes: Any additional relevant information

                Return only valid JSON with these fields. If information is not clearly visible, use null for that field.
                """
              },
              %{
                "type" => "image_url",
                "image_url" => %{
                  "url" => "data:image/jpeg;base64,#{base64_image}"
                }
              }
            ]
          }
        ],
        "max_tokens" => 300
      }

      case Req.post("https://api.openai.com/v1/chat/completions",
             headers: headers,
             json: body
           ) do
        {:ok, %{status: 200, body: response}} ->
          content = get_in(response, ["choices", Access.at(0), "message", "content"])
          parse_ai_response(content)

        {:error, _} ->
          %{}
      end
    else
      # Fallback: return demo data if no API key
      %{
        "name" => "Medicine Name (AI analysis requires OpenAI API key)",
        "type" => "Tablet",
        "quantity" => nil,
        "expiration_date" => nil,
        "notes" => "Set OPENAI_API_KEY environment variable to enable AI analysis"
      }
    end
  end

  defp parse_ai_response(content) when is_binary(content) do
    try do
      # Try to extract JSON from the response
      json_match = Regex.run(~r/\{.*\}/s, content)

      if json_match do
        Jason.decode!(List.first(json_match))
      else
        %{}
      end
    rescue
      _ -> %{}
    end
  end

  defp parse_ai_response(_), do: %{}

  defp consume_uploaded_photos(socket) do
    consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
      # Create a unique filename using the original name and timestamp
      timestamp = System.system_time(:millisecond)
      extension = Path.extname(entry.client_name)
      filename = "#{timestamp}_#{Path.basename(entry.client_name, extension)}#{extension}"

      dest = Path.join([:code.priv_dir(:medicine_inventory), "static", "uploads", filename])
      File.cp!(path, dest)
      {:ok, "/uploads/#{filename}"}
    end)
  end
end
