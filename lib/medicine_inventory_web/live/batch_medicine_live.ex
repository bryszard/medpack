defmodule MedicineInventoryWeb.BatchMedicineLive do
  use MedicineInventoryWeb, :live_view

  alias MedicineInventory.Medicines
  alias MedicineInventory.AI.ImageAnalyzer

  @impl true
  def mount(_params, _session, socket) do
    # Start with 3 empty entries
    initial_entries = create_empty_entries(3)

    # Configure individual uploads for each entry
    socket_with_uploads = configure_uploads_for_entries(socket, initial_entries)

    {:ok,
     socket_with_uploads
     |> assign(:entries, initial_entries)
     |> assign(:batch_status, :ready)
     |> assign(:selected_for_edit, nil)
     |> assign(:analyzing, false)
     |> assign(:analysis_progress, 0)
     |> assign(:show_results_grid, false)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    # Handle form validation (not used for file uploads with auto_upload: true)
    {:noreply, socket}
  end

  def handle_event("upload", _params, socket) do
    # This handles the form submit, but we'll process uploads automatically
    {:noreply, socket}
  end

  def handle_event("add_entries", %{"count" => count_str}, socket) do
    count = String.to_integer(count_str)
    current_entries = socket.assigns.entries
    new_entries = create_empty_entries(count, length(current_entries))
    updated_entries = current_entries ++ new_entries

    # Reconfigure uploads for new entries
    socket_with_uploads = configure_uploads_for_entries(socket, updated_entries)

    {:noreply,
     socket_with_uploads
     |> assign(:entries, updated_entries)}
  end

  def handle_event("remove_entry", %{"id" => entry_id}, socket) do
    updated_entries = Enum.reject(socket.assigns.entries, &(&1.id == entry_id))

    # Reconfigure uploads for remaining entries
    socket_with_uploads = configure_uploads_for_entries(socket, updated_entries)

    {:noreply,
     socket_with_uploads
     |> assign(:entries, updated_entries)}
  end

  def handle_event("analyze_all", _params, socket) do
    # Check if any entries have uploaded files by checking the actual upload state
    entries_with_files =
      socket.assigns.entries
      |> Enum.filter(fn entry ->
        upload_key = String.to_atom("entry_#{entry.number}_photos")
        uploads = Map.get(socket.assigns.uploads, upload_key, %{entries: []})
        uploads.entries != []
      end)

    if entries_with_files == [] do
      {:noreply, put_flash(socket, :error, "Please upload at least one photo first")}
    else
      # Update entries to reflect their current upload status
      updated_entries =
        socket.assigns.entries
        |> Enum.map(fn entry ->
          upload_key = String.to_atom("entry_#{entry.number}_photos")
          uploads = Map.get(socket.assigns.uploads, upload_key, %{entries: []})

          if uploads.entries != [] do
            %{entry | photo_uploaded: true, photo_entry: List.first(uploads.entries)}
          else
            entry
          end
        end)

      {:noreply,
       socket
       |> assign(:entries, updated_entries)
       |> assign(:analyzing, true)
       |> assign(:analysis_progress, 0)
       |> start_async(:analyze_batch, fn -> analyze_batch_photos(updated_entries) end)}
    end
  end

  def handle_event("approve_entry", %{"id" => entry_id}, socket) do
    updated_entries =
      Enum.map(socket.assigns.entries, fn entry ->
        if entry.id == entry_id do
          %{entry | approval_status: :approved}
        else
          entry
        end
      end)

    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_event("reject_entry", %{"id" => entry_id}, socket) do
    updated_entries =
      Enum.map(socket.assigns.entries, fn entry ->
        if entry.id == entry_id do
          %{entry | approval_status: :rejected}
        else
          entry
        end
      end)

    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_event("edit_entry", %{"id" => entry_id}, socket) do
    {:noreply, assign(socket, selected_for_edit: entry_id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, selected_for_edit: nil)}
  end

  def handle_event("retry_analysis", %{"id" => entry_id}, socket) do
    updated_entries =
      Enum.map(socket.assigns.entries, fn entry ->
        if entry.id == entry_id do
          %{entry | ai_analysis_status: :pending}
        else
          entry
        end
      end)

    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_event("remove_photo", %{"id" => entry_id}, socket) do
    updated_entries =
      Enum.map(socket.assigns.entries, fn entry ->
        if entry.id == entry_id do
          %{entry | photo_uploaded: false, photo_entry: nil}
        else
          entry
        end
      end)

    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_event(
        "save_entry_edit",
        %{"medicine" => medicine_params, "entry_id" => entry_id},
        socket
      ) do
    updated_entries =
      Enum.map(socket.assigns.entries, fn entry ->
        if entry.id == entry_id do
          %{entry | ai_results: medicine_params, approval_status: :approved}
        else
          entry
        end
      end)

    {:noreply,
     socket
     |> assign(:entries, updated_entries)
     |> assign(:selected_for_edit, nil)
     |> put_flash(:info, "Entry updated and approved")}
  end

  def handle_event("approve_all", _params, socket) do
    updated_entries =
      Enum.map(socket.assigns.entries, fn entry ->
        if entry.ai_analysis_status == :complete do
          %{entry | approval_status: :approved}
        else
          entry
        end
      end)

    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_event("save_approved", _params, socket) do
    approved_entries = Enum.filter(socket.assigns.entries, &(&1.approval_status == :approved))

    if approved_entries == [] do
      {:noreply, put_flash(socket, :error, "No approved entries to save")}
    else
      save_results = save_approved_medicines(approved_entries)
      handle_save_results(socket, save_results)
    end
  end

  def handle_event("clear_rejected", _params, socket) do
    updated_entries = Enum.reject(socket.assigns.entries, &(&1.approval_status == :rejected))
    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    # Find which upload this ref belongs to and cancel it
    socket_updated =
      socket.assigns.entries
      |> Enum.reduce(socket, fn entry, acc_socket ->
        upload_key = String.to_atom("entry_#{entry.number}_photos")
        cancel_upload(acc_socket, upload_key, ref)
      end)

    {:noreply, socket_updated}
  end

  def handle_event("toggle_results_grid", _params, socket) do
    {:noreply, assign(socket, show_results_grid: not socket.assigns.show_results_grid)}
  end

  @impl true
  def handle_info({:process_uploaded_file, entry, upload_entry}, socket) do
    require Logger
    Logger.info("Processing uploaded file for entry #{entry.id}: #{upload_entry.client_name}")

    # Find the upload key for this entry
    upload_key = String.to_atom("entry_#{entry.number}_photos")

    # Consume the uploaded file
    file_results =
      consume_uploaded_entries(socket, upload_key, fn meta, _upload_entry ->
        # Create destination path
        dest_dir = Path.join([System.tmp_dir(), "medicine_uploads"])
        File.mkdir_p!(dest_dir)
        dest_path = Path.join(dest_dir, "#{entry.id}_#{upload_entry.client_name}")

        # Copy file to destination
        File.cp!(meta.path, dest_path)

        # Return file info
        %{
          path: dest_path,
          filename: upload_entry.client_name,
          size: File.stat!(dest_path).size
        }
      end)

    case file_results do
      [%{path: file_path, filename: filename, size: size}] ->
        # Update the entry with file information
        updated_entry = %{
          entry
          | photo_uploaded: true,
            photo_path: file_path,
            photo_entry: %{client_name: filename, client_size: size},
            ai_analysis_status: :processing
        }

        updated_entries = replace_entry(socket.assigns.entries, updated_entry)

        # Start AI analysis immediately
        send(self(), {:analyze_photo, updated_entry})

        {:noreply,
         socket
         |> assign(entries: updated_entries)
         |> put_flash(:info, "Photo uploaded for entry #{entry.number}! Starting analysis...")}

      [] ->
        Logger.warning("No files to consume for entry #{entry.id}")
        {:noreply, socket}

      _ ->
        Logger.error("Multiple files uploaded for entry #{entry.id}")

        {:noreply,
         put_flash(socket, :error, "Multiple files uploaded, only one allowed per entry")}
    end
  end

  def handle_info({:analyze_photo, entry}, socket) do
    case ImageAnalyzer.analyze_medicine_photo(entry.photo_path) do
      {:ok, ai_results} ->
        updated_entry = %{
          entry
          | ai_analysis_status: :complete,
            ai_results: ai_results
        }

        updated_entries = replace_entry(socket.assigns.entries, updated_entry)

        {:noreply,
         socket
         |> assign(:entries, updated_entries)
         |> put_flash(
           :info,
           "Analysis complete for entry #{entry.number}! Review the extracted data."
         )}

      {:error, reason} ->
        updated_entry = %{
          entry
          | ai_analysis_status: :failed,
            validation_errors: ["AI analysis failed: #{inspect(reason)}"]
        }

        updated_entries = replace_entry(socket.assigns.entries, updated_entry)

        {:noreply,
         socket
         |> assign(:entries, updated_entries)
         |> put_flash(:error, "Analysis failed for entry #{entry.number}: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_async(:analyze_batch, {:ok, analysis_results}, socket) do
    updated_entries = apply_analysis_results(socket.assigns.entries, analysis_results)

    {:noreply,
     socket
     |> assign(:analyzing, false)
     |> assign(:entries, updated_entries)
     |> assign(:show_results_grid, true)
     |> put_flash(:info, "Batch analysis complete! Review results below.")}
  end

  def handle_async(:analyze_batch, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:analyzing, false)
     |> put_flash(:error, "Batch analysis failed. Please try again.")}
  end

  # Private functions

  defp handle_progress(upload_config_name, upload_entry, socket) do
    require Logger

    Logger.info(
      "Upload progress: #{upload_entry.progress}% for #{upload_entry.client_name} (config: #{upload_config_name})"
    )

    # When upload is complete (progress == 100), process the file
    if upload_entry.done? do
      Logger.info("Upload complete for config: #{upload_config_name}")

      # Find the entry that matches this upload config
      entry = find_entry_by_upload_config(socket.assigns.entries, upload_config_name)

      if entry do
        Logger.info("Upload complete for entry #{entry.id}, processing file...")
        send(self(), {:process_uploaded_file, entry, upload_entry})
      else
        Logger.warning("Could not find entry for upload config: #{upload_config_name}")
      end
    end

    {:noreply, socket}
  end

  defp replace_entry(entries, updated_entry) do
    Enum.map(entries, fn entry ->
      if entry.id == updated_entry.id do
        updated_entry
      else
        entry
      end
    end)
  end

  defp create_empty_entries(count, start_number \\ 0) do
    (start_number + 1)..(start_number + count)
    |> Enum.map(fn i ->
      %{
        id: "entry_#{System.unique_integer([:positive])}",
        number: i,
        photo_uploaded: false,
        photo_entry: nil,
        photo_path: nil,
        ai_analysis_status: :pending,
        ai_results: %{},
        approval_status: :pending,
        validation_errors: []
      }
    end)
  end

  defp configure_uploads_for_entries(socket, entries) do
    entries
    |> Enum.reduce(socket, fn entry, acc_socket ->
      upload_key = String.to_atom("entry_#{entry.number}_photos")

      allow_upload(acc_socket, upload_key,
        accept: ~w(.jpg .jpeg .png),
        max_entries: 1,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )
    end)
  end

  defp analyze_batch_photos(entries) do
    # Analyze each entry with a photo
    entries
    |> Enum.filter(& &1.photo_uploaded)
    |> Enum.map(fn entry ->
      ai_results = simulate_ai_analysis_for_entry(entry)
      {entry.id, ai_results}
    end)
  end

  defp simulate_ai_analysis_for_entry(_entry) do
    # Simulate AI analysis with varied results
    case :rand.uniform(3) do
      1 ->
        %{
          "name" => "Tylenol Extra Strength 500mg",
          "brand_name" => "Tylenol",
          "generic_name" => "Acetaminophen",
          "dosage_form" => "tablet",
          "active_ingredient" => "Acetaminophen",
          "strength_value" => 500.0,
          "strength_unit" => "mg",
          "container_type" => "bottle",
          "total_quantity" => 100.0,
          "remaining_quantity" => 100.0,
          "quantity_unit" => "tablets",
          "manufacturer" => "Johnson & Johnson"
        }

      2 ->
        %{
          "name" => "Advil Liqui-Gels 200mg",
          "brand_name" => "Advil",
          "generic_name" => "Ibuprofen",
          "dosage_form" => "capsule",
          "active_ingredient" => "Ibuprofen",
          "strength_value" => 200.0,
          "strength_unit" => "mg",
          "container_type" => "bottle",
          "total_quantity" => 80.0,
          "remaining_quantity" => 80.0,
          "quantity_unit" => "capsules",
          "manufacturer" => "Pfizer"
        }

      3 ->
        # Simulate failed analysis
        :failed
    end
  end

  defp apply_analysis_results(entries, analysis_results) do
    analysis_map = Map.new(analysis_results)

    Enum.map(entries, fn entry ->
      case Map.get(analysis_map, entry.id) do
        nil ->
          entry

        :failed ->
          %{entry | ai_analysis_status: :failed}

        ai_results ->
          %{entry | ai_analysis_status: :complete, ai_results: ai_results}
      end
    end)
  end

  defp save_approved_medicines(approved_entries) do
    approved_entries
    |> Enum.map(fn entry ->
      case Medicines.create_medicine(entry.ai_results) do
        {:ok, medicine} -> {:ok, medicine}
        {:error, changeset} -> {:error, entry.id, changeset}
      end
    end)
  end

  defp handle_save_results(socket, save_results) do
    successes = Enum.count(save_results, &match?({:ok, _}, &1))
    failures = Enum.count(save_results, &match?({:error, _, _}, &1))

    message =
      if failures == 0 do
        "Successfully saved #{successes} medicines to your inventory!"
      else
        "Saved #{successes} medicines. #{failures} failed to save."
      end

    # Remove successfully saved entries
    remaining_entries =
      if successes > 0 do
        successful_indices = get_successful_entry_indices(save_results)

        Enum.reject(socket.assigns.entries, fn entry ->
          entry.approval_status == :approved and entry.id not in successful_indices
        end)
      else
        socket.assigns.entries
      end

    # Broadcast updates to other clients
    if successes > 0 do
      Phoenix.PubSub.broadcast(
        MedicineInventory.PubSub,
        "medicines",
        {:batch_medicines_created, successes}
      )
    end

    {:noreply,
     socket
     |> assign(:entries, remaining_entries)
     |> put_flash(:info, message)}
  end

  defp get_successful_entry_indices(save_results) do
    save_results
    |> Enum.with_index()
    |> Enum.filter(&match?({{:ok, _}, _}, &1))
    |> Enum.map(fn {{:ok, _}, _index} -> nil end)
    |> Enum.reject(&is_nil/1)
  end

  # Helper functions for the template
  def entry_status_icon(entry) do
    case {entry.photo_uploaded, entry.ai_analysis_status, entry.approval_status} do
      {false, _, _} -> "⬆️"
      {true, :pending, _} -> "📸"
      {true, :processing, _} -> "🔍"
      {true, :complete, :pending} -> "⏳"
      {true, :complete, :approved} -> "✅"
      {true, :complete, :rejected} -> "❌"
      {true, :failed, _} -> "⚠️"
    end
  end

  def entry_status_text(entry) do
    case {entry.photo_uploaded, entry.ai_analysis_status, entry.approval_status} do
      {false, _, _} -> "Ready for upload"
      {true, :pending, _} -> "Photo uploaded"
      {true, :processing, _} -> "Analyzing photo..."
      {true, :complete, :pending} -> "Pending review"
      {true, :complete, :approved} -> "Approved"
      {true, :complete, :rejected} -> "Rejected"
      {true, :failed, _} -> "Analysis failed"
    end
  end

  def ai_results_summary(ai_results) when is_map(ai_results) and map_size(ai_results) > 0 do
    name = Map.get(ai_results, "name", "Unknown")
    form = Map.get(ai_results, "dosage_form", "")

    strength =
      "#{Map.get(ai_results, "strength_value", "")}#{Map.get(ai_results, "strength_unit", "")}"

    "#{name} • #{String.capitalize(form)} • #{strength}"
  end

  def ai_results_summary(_), do: "No analysis data"

  # Helper to get upload key for an entry
  def get_upload_key_for_entry(entry) do
    String.to_atom("entry_#{entry.number}_photos")
  end

  # Check if entry has uploaded files
  def entry_has_uploaded_files?(entry, uploads) do
    upload_key = get_upload_key_for_entry(entry)
    upload_config = Map.get(uploads, upload_key, %{entries: []})
    upload_config.entries != []
  end

  # Get upload entries for a specific entry
  def get_upload_entries_for_entry(entry, uploads) do
    upload_key = get_upload_key_for_entry(entry)
    upload_config = Map.get(uploads, upload_key, %{entries: []})
    upload_config.entries
  end

  # Helper function to render field extraction status
  def render_field_status(entry, field_key, field_name) do
    value = Map.get(entry.ai_results || %{}, field_key)

    case value do
      nil ->
        assigns = %{field_name: field_name}

        ~H"""
        <div class="flex items-center justify-between">
          <span class="text-gray-600">{@field_name}:</span>
          <span class="text-red-600 text-xs">❌ Not detected</span>
        </div>
        """

      "" ->
        assigns = %{field_name: field_name}

        ~H"""
        <div class="flex items-center justify-between">
          <span class="text-gray-600">{@field_name}:</span>
          <span class="text-red-600 text-xs">❌ Not detected</span>
        </div>
        """

      _ ->
        formatted_value = format_field_value(field_key, value)
        assigns = %{field_name: field_name, value: formatted_value}

        ~H"""
        <div class="flex items-center justify-between">
          <span class="text-gray-800">{@field_name}:</span>
          <span class="text-green-700 font-medium">✅ {@value}</span>
        </div>
        """
    end
  end

  # Helper to format field values for display
  defp format_field_value("dosage_form", value), do: String.capitalize(value)

  defp format_field_value("container_type", value),
    do: String.capitalize(String.replace(value, "_", " "))

  defp format_field_value("strength_value", value) when is_number(value), do: "#{value}"
  defp format_field_value("total_quantity", value) when is_number(value), do: "#{value}"
  defp format_field_value("remaining_quantity", value) when is_number(value), do: "#{value}"
  defp format_field_value(_field, value), do: "#{value}"

  # Helper to get missing required fields
  def get_missing_required_fields(entry) do
    required_fields = [
      {"name", "Medicine Name"},
      {"dosage_form", "Dosage Form"},
      {"active_ingredient", "Active Ingredient"},
      {"strength_value", "Strength Value"},
      {"strength_unit", "Strength Unit"},
      {"container_type", "Container Type"},
      {"total_quantity", "Total Quantity"},
      {"remaining_quantity", "Remaining Quantity"},
      {"quantity_unit", "Quantity Unit"}
    ]

    ai_results = entry.ai_results || %{}

    required_fields
    |> Enum.filter(fn {field_key, _field_name} ->
      value = Map.get(ai_results, field_key)
      is_nil(value) or value == ""
    end)
    |> Enum.map(fn {_field_key, field_name} -> field_name end)
  end

  defp find_entry_by_number(entries, number) do
    Enum.find(entries, &(&1.number == number))
  end

  defp find_entry_by_upload_config(entries, upload_config_name) do
    # The upload_config_name is an atom like :entry_1_photos
    # Extract the entry number from it
    upload_config_str = Atom.to_string(upload_config_name)

    case Regex.run(~r/entry_(\d+)_photos/, upload_config_str) do
      [_, number_str] ->
        number = String.to_integer(number_str)
        find_entry_by_number(entries, number)

      _ ->
        nil
    end
  end
end
