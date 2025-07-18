defmodule MedpackWeb.MedicineShowLive do
  use MedpackWeb, :live_view

  require Logger

  alias Medpack.Medicines
  alias Medpack.AI.ImageAnalyzer

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    try do
      case Medicines.get_medicine(id) do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, "Medicine not found")
           |> push_navigate(to: ~p"/inventory")}

        medicine ->
          photo_paths = medicine.photo_paths || []
          default_index =
            if is_binary(medicine.default_photo_path) and medicine.default_photo_path in photo_paths do
              Enum.find_index(photo_paths, &(&1 == medicine.default_photo_path)) || 0
            else
              0
            end

          {:ok,
           socket
           |> assign(:medicine, medicine)
           |> assign(:page_title, medicine.name)
           |> assign(:selected_photo_index, default_index)
           |> assign(:show_enlarged_photo, false)
           |> assign(:enlarged_photo_index, default_index)
           |> assign(:edit_mode, false)
           |> assign(:form, to_form(Medpack.Medicine.form_changeset(medicine)))
           |> assign(:analyzing, false)
           |> assign(:upload_progress, 0)
           |> assign(:slider_debounce_timer, nil)
           |> allow_upload(:photos,
             accept: ~w(.jpg .jpeg .png),
             max_entries: 3,
             max_file_size: 10_000_000,
             auto_upload: true,
             progress: &handle_progress/3
           )}
      end
    rescue
      Ecto.Query.CastError ->
        {:ok,
         socket
         |> put_flash(:error, "Medicine not found")
         |> push_navigate(to: ~p"/inventory")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_photo", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    {:noreply, assign(socket, selected_photo_index: index)}
  end

  def handle_event("enlarge_photo", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    {:noreply,
     socket
     |> assign(show_enlarged_photo: true)
     |> assign(enlarged_photo_index: index)}
  end

  def handle_event("close_enlarged_photo", _params, socket) do
    {:noreply, assign(socket, show_enlarged_photo: false)}
  end

  def handle_event("previous_photo", _params, socket) do
    photo_count = length(socket.assigns.medicine.photo_paths)
    current_index = socket.assigns.enlarged_photo_index
    new_index = if current_index == 0, do: photo_count - 1, else: current_index - 1

    {:noreply,
     socket
     |> assign(enlarged_photo_index: new_index)
     |> assign(selected_photo_index: new_index)}
  end

  def handle_event("next_photo", _params, socket) do
    photo_count = length(socket.assigns.medicine.photo_paths)
    current_index = socket.assigns.enlarged_photo_index
    new_index = if current_index == photo_count - 1, do: 0, else: current_index + 1

    {:noreply,
     socket
     |> assign(enlarged_photo_index: new_index)
     |> assign(selected_photo_index: new_index)}
  end

  def handle_event("modal_content_click", _params, socket) do
    # Prevents event bubbling to background
    {:noreply, socket}
  end

  def handle_event("edit_medicine", _params, socket) do
    {:noreply, assign(socket, edit_mode: true)}
  end

  def handle_event("toggle_edit", _params, socket) do
    new_edit_mode = !socket.assigns.edit_mode

    if new_edit_mode do
      {:noreply, assign(socket, edit_mode: true)}
    else
      {:noreply,
       socket
       |> assign(edit_mode: false)
       |> assign(form: to_form(Medpack.Medicine.form_changeset(socket.assigns.medicine)))}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(edit_mode: false)
     |> assign(form: to_form(Medpack.Medicine.form_changeset(socket.assigns.medicine)))}
  end

  def handle_event("validate", %{"medicine" => medicine_params}, socket) do
    changeset =
      socket.assigns.medicine
      |> Medicines.change_medicine(medicine_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("validate", _params, socket) do
    # Handle file upload validation (called when files are selected)
    {:noreply, socket}
  end

  def handle_event("upload", _params, socket) do
    # Handle form submit for file uploads (not used with auto_upload: true)
    {:noreply, socket}
  end

  def handle_event("save", %{"medicine" => medicine_params}, socket) do
    # Get fresh medicine data from database to avoid stale data issues
    current_medicine = Medicines.get_medicine!(socket.assigns.medicine.id)

    case Medicines.update_medicine(current_medicine, medicine_params) do
      {:ok, medicine} ->
        {:noreply,
         socket
         |> assign(medicine: medicine)
         |> assign(edit_mode: false)
         |> assign(form: to_form(Medpack.Medicine.form_changeset(medicine)))
         |> put_flash(:info, "Medicine updated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("remove_photo", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    medicine = socket.assigns.medicine

    if index >= 0 and index < length(medicine.photo_paths) do
      # Remove the photo at the specified index
      photo_to_remove = Enum.at(medicine.photo_paths, index)
      updated_photo_paths = List.delete_at(medicine.photo_paths, index)

      # Clean up the physical file
      if photo_to_remove do
        Medpack.FileManager.delete_file(photo_to_remove)
      end

      # Update the medicine in the database
      attrs =
        if medicine.default_photo_path == photo_to_remove do
          %{ "photo_paths" => updated_photo_paths, "default_photo_path" => List.first(updated_photo_paths) }
        else
          %{ "photo_paths" => updated_photo_paths }
        end

      case Medicines.update_medicine(medicine, attrs) do
        {:ok, updated_medicine} ->
          # Adjust selected photo index if necessary
          new_selected_index =
            cond do
              updated_photo_paths == [] -> 0
              index >= length(updated_photo_paths) -> length(updated_photo_paths) - 1
              true -> index
            end

          {:noreply,
           socket
           |> assign(medicine: updated_medicine)
           |> assign(selected_photo_index: new_selected_index)
           |> assign(form: to_form(Medpack.Medicine.form_changeset(updated_medicine)))
           |> put_flash(:info, "Photo removed successfully")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to remove photo")}
      end
    else
      {:noreply, put_flash(socket, :error, "Invalid photo index")}
    end
  end

  def handle_event("analyze_photos", _params, socket) do
    medicine = socket.assigns.medicine

    if medicine.photo_paths != [] do
      {:noreply,
       socket
       |> assign(:analyzing, true)
       |> start_async(:analyze_photos, fn -> analyze_medicine_photos(medicine.photo_paths) end)}
    else
      {:noreply, put_flash(socket, :error, "No photos to analyze")}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  def handle_event("update_remaining_quantity", %{"remaining_quantity" => value_str}, socket) do
    # Cancel existing timer if it exists
    if socket.assigns.slider_debounce_timer do
      Process.cancel_timer(socket.assigns.slider_debounce_timer)
    end

    # Update the UI immediately for responsive feedback
    try do
      new_remaining = Decimal.new(value_str)
      medicine = socket.assigns.medicine

      # Ensure the value is within valid bounds using Decimal arithmetic
      zero = Decimal.new("0")
      total_quantity = medicine.total_quantity

      clamped_remaining =
        new_remaining
        |> Decimal.max(zero)
        |> Decimal.min(total_quantity)

      # Update medicine in memory for immediate UI feedback
      updated_medicine = %{medicine | remaining_quantity: clamped_remaining}

      # Set a timer to actually save to database after 1000ms of inactivity
      timer_ref = Process.send_after(self(), {:save_remaining_quantity, clamped_remaining}, 1000)

      {:noreply,
       socket
       |> assign(medicine: updated_medicine)
       |> assign(form: to_form(Medicines.change_medicine(updated_medicine)))
       |> assign(slider_debounce_timer: timer_ref)}
    rescue
      _error ->
        {:noreply, put_flash(socket, :error, "Invalid quantity value")}
    end
  end

  def handle_event("delete_medicine", _params, socket) do
    case Medicines.delete_medicine(socket.assigns.medicine) do
      {:ok, _medicine} ->
        {:noreply,
         socket
         |> put_flash(:info, "Medicine deleted successfully")
         |> redirect(to: ~p"/inventory")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete medicine")}
    end
  end

  @impl true
  def handle_event("set_default_photo", %{"path" => path}, socket) do
    medicine = socket.assigns.medicine
    if path in (medicine.photo_paths || []) do
      case Medpack.Medicines.update_medicine(medicine, %{"default_photo_path" => path}) do
        {:ok, updated_medicine} ->
          {:noreply,
           socket
           |> assign(medicine: updated_medicine)
           |> assign(form: to_form(Medpack.Medicine.form_changeset(updated_medicine)))
           |> put_flash(:info, "Default photo updated!")}
        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to set default photo")}
      end
    else
      {:noreply, put_flash(socket, :error, "Invalid photo path")}
    end
  end

  @impl true
  def handle_async(:analyze_photos, {:ok, analysis_results}, socket) do
    case analysis_results do
      {:ok, ai_results} ->
        # Filter out remaining_quantity from AI results to preserve manual quantity management
        filtered_ai_results = Map.delete(ai_results, "remaining_quantity")

        # Apply filtered AI results to form
        updated_form =
          to_form(Medpack.Medicine.form_changeset(socket.assigns.medicine, filtered_ai_results))

        {:noreply,
         socket
         |> assign(:analyzing, false)
         |> assign(:form, updated_form)
         |> put_flash(
           :info,
           "AI analysis completed! Review the suggested values and save to apply changes."
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:analyzing, false)
         |> put_flash(:error, "AI analysis failed: #{reason}")}
    end
  end

  def handle_async(:analyze_photos, {:exit, reason}, socket) do
    Logger.error("AI analysis process exited: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:analyzing, false)
     |> put_flash(:error, "AI analysis failed unexpectedly")}
  end

  @impl true
  def handle_info({:process_uploaded_files}, socket) do
    # Process all uploaded files using the robust auto-upload handler
    file_results =
      consume_uploaded_entries(socket, :photos, fn meta, upload_entry ->
        case Medpack.FileManager.save_auto_uploaded_file(meta, upload_entry, "medicine_#{socket.assigns.medicine.id}") do
          {:ok, result} when is_binary(result) ->
            # Local storage - convert to web path for storage
            web_path = Medpack.FileManager.get_photo_url(result)
            {:ok, web_path}

          {:ok, %{s3_key: _s3_key, url: url}} ->
            # S3 storage - return the URL for display
            {:ok, url}

          {:error, reason} ->
            {:error, reason}
        end
      end)

    case file_results do
      file_identifiers when is_list(file_identifiers) and length(file_identifiers) > 0 ->
        medicine = socket.assigns.medicine
        updated_photo_paths = medicine.photo_paths ++ file_identifiers

        # Update the medicine in the database with new photos
        case Medicines.update_medicine(medicine, %{"photo_paths" => updated_photo_paths}) do
          {:ok, updated_medicine} ->
            {:noreply,
             socket
             |> assign(medicine: updated_medicine)
             |> assign(form: to_form(Medpack.Medicine.form_changeset(updated_medicine)))
             |> put_flash(:info, "Photos uploaded successfully!")}

          {:error, _changeset} ->
            # Clean up uploaded files if database update fails
            Enum.each(file_identifiers, fn file_identifier ->
              Medpack.FileManager.delete_file(file_identifier)
            end)

            {:noreply, put_flash(socket, :error, "Failed to save uploaded photos")}
        end

      [] ->
        {:noreply, socket}

      _error ->
        {:noreply, put_flash(socket, :error, "Failed to upload photos")}
    end
  end

  @impl true
  def handle_info({:medicine_updated, medicine}, socket) do
    {:noreply, assign(socket, medicine: medicine)}
  end

  @impl true
  def handle_info({:ai_analysis_complete, analysis_result}, socket) do
    # Filter out remaining_quantity from AI results to preserve manual quantity management
    filtered_ai_results = Map.delete(analysis_result, "remaining_quantity")

    # Apply filtered AI results to form
    updated_form =
      to_form(Medpack.Medicine.form_changeset(socket.assigns.medicine, filtered_ai_results))

    {:noreply,
     socket
     |> assign(:analyzing, false)
     |> assign(:form, updated_form)
     |> put_flash(
       :info,
       "AI analysis completed! Review the suggested values and save to apply changes."
     )}
  end

  @impl true
  def handle_info({:upload_error, error_message}, socket) do
    Logger.warning("Upload error handled gracefully: #{error_message}")

    {:noreply,
     socket
     |> put_flash(:error, "Upload failed: #{error_message}")}
  end

  def handle_info({:save_remaining_quantity, remaining_quantity}, socket) do
    # Get the current medicine ID, but use the passed remaining_quantity value
    medicine_id = socket.assigns.medicine.id

    # Get fresh medicine data from database to avoid stale data issues
    current_medicine = Medicines.get_medicine!(medicine_id)

    case Medicines.update_medicine(current_medicine, %{"remaining_quantity" => remaining_quantity}) do
      {:ok, updated_medicine} ->
        # Reload from database to ensure we have the latest data
        reloaded_medicine = Medicines.get_medicine!(updated_medicine.id)

        {:noreply,
         socket
         |> assign(medicine: reloaded_medicine)
         |> assign(form: to_form(Medpack.Medicine.form_changeset(reloaded_medicine)))
         |> assign(slider_debounce_timer: nil)
         |> put_flash(
           :info,
           "Quantity updated: #{reloaded_medicine.remaining_quantity} #{reloaded_medicine.quantity_unit}"
         )}

      {:error, changeset} ->
        Logger.error("Failed to update remaining quantity: #{inspect(changeset.errors)}")

        {:noreply,
         socket
         |> assign(slider_debounce_timer: nil)
         |> put_flash(:error, "Failed to save remaining quantity")}
    end
  end

  # Progress handler for file uploads
  defp handle_progress(:photos, upload_entry, socket) do
    if upload_entry.done? do
      # Check if all uploads are complete
      all_done? = Enum.all?(socket.assigns.uploads.photos.entries, & &1.done?)

      if all_done? do
        send(self(), {:process_uploaded_files})
      end
    end

    # Calculate overall progress
    total_progress =
      if socket.assigns.uploads.photos.entries == [] do
        0
      else
        socket.assigns.uploads.photos.entries
        |> Enum.map(& &1.progress)
        |> Enum.sum()
        |> div(length(socket.assigns.uploads.photos.entries))
      end

    {:noreply, assign(socket, upload_progress: total_progress)}
  end

  # AI Analysis helper
  defp analyze_medicine_photos(photo_paths) do
    # Convert photo paths to processable paths/URLs
    processable_paths =
      Enum.map(photo_paths, fn photo_path ->
        if Medpack.FileManager.use_s3_storage?() do
          # For S3, photo_path is already the S3 key or URL
          if String.starts_with?(photo_path, "http") do
            # Already a URL
            photo_path
          else
            Medpack.S3FileManager.get_presigned_url(photo_path)
          end
        else
          # For local files, convert web path to absolute filesystem path
          case photo_path do
            "/uploads/" <> relative_path ->
              # Web path format - convert to absolute path
              upload_base = Medpack.FileManager.get_upload_path()
              Path.join([upload_base, relative_path])

            _ ->
              # Legacy format - might be just filename
              upload_base = Medpack.FileManager.get_upload_path()
              Path.join([upload_base, photo_path])
          end
        end
      end)
      # Remove any nil URLs (failed presigned URL generation)
      |> Enum.reject(&is_nil/1)

    case processable_paths do
      [] ->
        {:error, "No valid photo paths available for analysis"}

      [single_path] ->
        ImageAnalyzer.analyze_medicine_photo(single_path)

      multiple_paths ->
        ImageAnalyzer.analyze_medicine_photos(multiple_paths)
    end
  end

  # Helper function to convert upload errors to strings
  defp error_to_string(:too_large), do: "File is too large (max 10MB)"
  defp error_to_string(:too_many_files), do: "Too many files (max 3)"
  defp error_to_string(:not_accepted), do: "File type not supported (only JPG, PNG)"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"

  # Helper function to get displayable photo URL
  def photo_url(photo_identifier) do
    Medpack.FileManager.get_photo_url(photo_identifier)
  end


end
