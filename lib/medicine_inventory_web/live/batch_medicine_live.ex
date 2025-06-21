defmodule MedicineInventoryWeb.BatchMedicineLive do
  use MedicineInventoryWeb, :live_view

  alias MedicineInventory.{Medicines, Medicine}

  @impl true
  def mount(_params, _session, socket) do
    # Start with 3 empty entries
    initial_entries = create_empty_entries(3)

    {:ok,
     socket
     |> assign(:entries, initial_entries)
     |> assign(:batch_status, :ready)
     |> assign(:selected_for_edit, nil)
     |> assign(:analyzing, false)
     |> assign(:analysis_progress, 0)
     |> assign(:show_results_grid, false)
     |> allow_upload(:batch_photos,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 20,
       max_file_size: 10_000_000
     )
     |> assign_upload_refs_to_entries()
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_entries", %{"count" => count_str}, socket) do
    count = String.to_integer(count_str)
    new_entries = create_empty_entries(count)
    updated_entries = socket.assigns.entries ++ new_entries

    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_event("remove_entry", %{"id" => entry_id}, socket) do
    updated_entries = Enum.reject(socket.assigns.entries, &(&1.id == entry_id))
    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_event("upload_photo", %{"entry_id" => entry_id}, socket) do
    # Handle individual photo upload for specific entry
    case find_upload_for_entry(socket, entry_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "No photo uploaded for this entry")}

      entry ->
        updated_entries =
          Enum.map(socket.assigns.entries, fn batch_entry ->
            if batch_entry.id == entry_id do
              %{batch_entry | photo_uploaded: true, photo_entry: entry}
            else
              batch_entry
            end
          end)

        {:noreply, assign(socket, entries: updated_entries)}
    end
  end

  def handle_event("analyze_all", _params, socket) do
    entries_with_photos = Enum.filter(socket.assigns.entries, & &1.photo_uploaded)

    if entries_with_photos == [] do
      {:noreply, put_flash(socket, :error, "Please upload at least one photo first")}
    else
      {:noreply,
       socket
       |> assign(:analyzing, true)
       |> assign(:analysis_progress, 0)
       |> start_async(:analyze_batch, fn -> analyze_batch_photos(entries_with_photos) end)}
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

  def handle_event("toggle_results_grid", _params, socket) do
    {:noreply, assign(socket, show_results_grid: not socket.assigns.show_results_grid)}
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

  defp create_empty_entries(count) do
    1..count
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

  defp find_upload_for_entry(socket, entry_id) do
    # This would find the uploaded file for the specific entry
    # For now, return the first uploaded entry
    List.first(socket.assigns.uploads.batch_photos.entries)
  end

  defp analyze_batch_photos(entries) do
    # Analyze each entry with a photo
    entries
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
end
