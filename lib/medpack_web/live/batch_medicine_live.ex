defmodule MedpackWeb.BatchMedicineLive do
  @moduledoc """
  LiveView for batch medicine entry processing.

  This version uses helper modules and components to dramatically reduce
  complexity and improve maintainability.
  """

  use MedpackWeb, :live_view

  require Logger

  # Import helper modules
  alias MedpackWeb.BatchMedicineLive.{UploadHandler, EntryManager, AnalysisCoordinator}
  alias Medpack.BatchProcessing

  @impl true
  def mount(_params, _session, socket) do
    # Generate a unique batch_id for this session
    batch_id = generate_batch_id()

    # Start with in-memory entries only - create DB entries when photos are uploaded
    initial_entries = EntryManager.create_empty_entries(3)

    # Configure individual uploads for each entry
    socket_with_uploads = UploadHandler.configure_uploads_for_entries(socket, initial_entries)

    # Subscribe to analysis updates
    Phoenix.PubSub.subscribe(Medpack.PubSub, "batch_processing")

    {:ok,
     socket_with_uploads
     |> assign(:entries, initial_entries)
     |> assign(:batch_id, batch_id)
     |> assign(:batch_status, :ready)
     |> assign(:selected_for_edit, nil)
     |> assign(:analyzing, false)
     |> assign(:analysis_progress, 0)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # Form validation handlers
  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}
  def handle_event("upload", _params, socket), do: {:noreply, socket}

  def handle_event("validate_entry_edit", _params, socket) do
    # For now, just return socket without validation
    # Later we could add client-side validation feedback
    {:noreply, socket}
  end

  # Entry management events
  def handle_event("add_entries", %{"count" => count_str}, socket) do
    count = String.to_integer(count_str)
    current_entries = socket.assigns.entries

    new_entries = EntryManager.create_empty_entries(count, length(current_entries))
    updated_entries = current_entries ++ new_entries

    socket_with_uploads = UploadHandler.configure_uploads_for_entries(socket, updated_entries)

    {:noreply, assign(socket_with_uploads, :entries, updated_entries)}
  end

  def handle_event("add_ghost_entry", _params, socket) do
    current_entries = socket.assigns.entries
    new_entry = EntryManager.create_empty_entries(1, length(current_entries))
    updated_entries = current_entries ++ new_entry

    socket_with_uploads = UploadHandler.configure_uploads_for_entries(socket, updated_entries)

    {:noreply, assign(socket_with_uploads, :entries, updated_entries)}
  end

  def handle_event("remove_entry", %{"id" => entry_id}, socket) do
    updated_entries = EntryManager.remove_entry(socket.assigns.entries, entry_id)
    socket_with_uploads = UploadHandler.configure_uploads_for_entries(socket, updated_entries)

    {:noreply, assign(socket_with_uploads, :entries, updated_entries)}
  end

  # Photo management events
  def handle_event("remove_photo", %{"id" => entry_id, "photo_index" => photo_index_str}, socket) do
    photo_index = String.to_integer(photo_index_str)

    # Handle database photo deletion if needed
    if is_integer(EntryManager.normalize_entry_id(entry_id)) do
      case BatchProcessing.remove_entry_photo_by_index(entry_id, photo_index) do
        {:ok, :photo_removed} ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to remove photo from database: #{inspect(reason)}")
      end
    end

    updated_entries =
      EntryManager.remove_entry_photo(socket.assigns.entries, entry_id, photo_index)

    {:noreply,
     socket
     |> assign(entries: updated_entries)
     |> put_flash(:info, "Photo removed successfully")}
  end

  def handle_event("remove_all_photos", %{"id" => entry_id}, socket) do
    # Handle database photo deletion if needed
    if is_integer(EntryManager.normalize_entry_id(entry_id)) do
      case BatchProcessing.remove_all_entry_photos(entry_id) do
        {:ok, :all_photos_removed} ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to remove photos from database: #{inspect(reason)}")
      end
    end

    updated_entries = EntryManager.remove_all_entry_photos(socket.assigns.entries, entry_id)

    {:noreply,
     socket
     |> assign(entries: updated_entries)
     |> put_flash(:info, "All photos removed successfully")}
  end

  # Analysis events
  def handle_event("analyze_all", _params, socket) do
    case AnalysisCoordinator.analyze_batch_entries(socket.assigns.entries) do
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}

      {:ok, _analysis_results} ->
        entries = socket.assigns.entries

        {:noreply,
         socket
         |> assign(:analyzing, true)
         |> assign(:analysis_progress, 0)
         |> start_async(:analyze_batch, fn ->
           AnalysisCoordinator.analyze_batch_entries(entries)
         end)}
    end
  end

  def handle_event("analyze_now", %{"id" => entry_id}, socket) do
    case AnalysisCoordinator.trigger_entry_analysis(socket.assigns.entries, entry_id) do
      {updated_entries, {:info, message}} ->
        {:noreply,
         socket
         |> assign(entries: updated_entries)
         |> put_flash(:info, message)}

      {updated_entries, {:error, message}} ->
        {:noreply,
         socket
         |> assign(entries: updated_entries)
         |> put_flash(:error, message)}

      {updated_entries, nil} ->
        {:noreply, assign(socket, entries: updated_entries)}
    end
  end

  def handle_event("retry_analysis", %{"id" => entry_id}, socket) do
    case AnalysisCoordinator.retry_entry_analysis(socket.assigns.entries, entry_id) do
      {updated_entries, flash_info} when is_tuple(flash_info) ->
        {flash_type, message} = flash_info

        {:noreply,
         socket
         |> assign(entries: updated_entries)
         |> put_flash(flash_type, message)}

      {updated_entries, _} ->
        {:noreply, assign(socket, entries: updated_entries)}
    end
  end

  # Approval events
  def handle_event("approve_entry", %{"id" => entry_id}, socket) do
    updated_entries =
      EntryManager.update_entry_approval_status(socket.assigns.entries, entry_id, :approved)

    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_event("reject_entry", %{"id" => entry_id}, socket) do
    updated_entries =
      EntryManager.update_entry_approval_status(socket.assigns.entries, entry_id, :rejected)

    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_event("approve_all", _params, socket) do
    updated_entries = EntryManager.approve_all_complete_entries(socket.assigns.entries)
    {:noreply, assign(socket, entries: updated_entries)}
  end

  # Edit events
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
      EntryManager.update_entry_medicine_data(socket.assigns.entries, entry_id, medicine_params)

    {:noreply,
     socket
     |> assign(:entries, updated_entries)
     |> assign(:selected_for_edit, nil)
     |> put_flash(:info, "Entry updated and approved")}
  end

  # Alternative save handler for test compatibility
  def handle_event("save_entry_edit", params, socket) when is_map(params) do
    entry_id = Map.get(params, "id")

    if entry_id do
      entry_updates = Map.drop(params, ["id"])

      updated_entries =
        Enum.map(socket.assigns.entries, fn entry ->
          if EntryManager.normalize_entry_id(entry.id) ==
               EntryManager.normalize_entry_id(entry_id) do
            updates =
              Enum.reduce(entry_updates, %{}, fn {k, v}, acc ->
                Map.put(acc, String.to_atom(k), v)
              end)

            Map.merge(entry, updates)
          else
            entry
          end
        end)

      {:noreply,
       socket
       |> assign(:entries, updated_entries)
       |> assign(:selected_for_edit, nil)}
    else
      {:noreply, socket}
    end
  end

  # Save events
  def handle_event("save_approved", _params, socket) do
    approved_entries = EntryManager.get_approved_entries(socket.assigns.entries)

    if approved_entries == [] do
      {:noreply, put_flash(socket, :error, "No approved entries to save")}
    else
      try do
        save_results =
          case BatchProcessing.save_approved_medicines(socket.assigns.batch_id) do
            {:ok, %{results: results}} -> results
            {:error, _reason} -> []
          end

        handle_save_results(socket, save_results)
      rescue
        e ->
          Logger.error("Error saving approved entries: #{inspect(e)}")
          {:noreply, put_flash(socket, :error, "Failed to save entries: #{Exception.message(e)}")}
      end
    end
  end

  def handle_event("save_single_entry", %{"id" => entry_id}, socket) do
    case Enum.find(
           socket.assigns.entries,
           &(EntryManager.normalize_entry_id(&1.id) == EntryManager.normalize_entry_id(entry_id))
         ) do
      nil ->
        {:noreply, put_flash(socket, :error, "Entry not found")}

      entry when entry.approval_status != :approved ->
        {:noreply, put_flash(socket, :error, "Entry must be approved before saving")}

      entry ->
        handle_single_entry_save(socket, entry, entry_id)
    end
  end

  # UI events
  def handle_event("clear_rejected", _params, socket) do
    updated_entries = EntryManager.clear_rejected_entries(socket.assigns.entries)
    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    socket_updated =
      socket.assigns.entries
      |> Enum.reduce(socket, fn entry, acc_socket ->
        upload_key = UploadHandler.get_upload_key_for_entry(entry)
        cancel_upload(acc_socket, upload_key, ref)
      end)

    {:noreply, socket_updated}
  end

  # File upload handling
  @impl true
  def handle_info({:process_all_uploaded_files, entry, upload_config_name}, socket) do
    case UploadHandler.process_uploaded_files(socket, entry, upload_config_name) do
      {updated_entries, {:info, message}} ->
        {:noreply,
         socket
         |> assign(entries: updated_entries)
         |> put_flash(:info, message)}

      {updated_entries, {:error, message}} ->
        {:noreply,
         socket
         |> assign(entries: updated_entries)
         |> put_flash(:error, message)}

      {updated_entries, nil} ->
        {:noreply, assign(socket, entries: updated_entries)}
    end
  end

  # Keep old handler for backward compatibility
  def handle_info({:process_uploaded_file, entry, _upload_entry}, socket) do
    upload_config_name = UploadHandler.get_upload_key_for_entry(entry)
    send(self(), {:process_all_uploaded_files, entry, upload_config_name})
    {:noreply, socket}
  end

  # Analysis timer handling
  def handle_info({:cancel_analysis_timer, entry_id}, socket) do
    updated_entries = AnalysisCoordinator.cancel_analysis_timer(socket.assigns.entries, entry_id)
    {:noreply, assign(socket, entries: updated_entries)}
  end

  def handle_info({:start_analysis_countdown, entry_id, seconds}, socket) do
    case AnalysisCoordinator.handle_analysis_countdown(socket.assigns.entries, entry_id, seconds) do
      {updated_entries, flash_info} when is_tuple(flash_info) ->
        {flash_type, message} = flash_info

        {:noreply,
         socket
         |> assign(entries: updated_entries)
         |> put_flash(flash_type, message)}

      {updated_entries, nil} ->
        {:noreply, assign(socket, entries: updated_entries)}

      updated_entries when is_list(updated_entries) ->
        {:noreply, assign(socket, entries: updated_entries)}
    end
  end

  def handle_info({:countdown_tick, entry_id, seconds}, socket) do
    send(self(), {:start_analysis_countdown, entry_id, seconds})
    {:noreply, socket}
  end

  # Analysis updates from Oban jobs via PubSub
  def handle_info({:analysis_update, update_data}, socket) do
    updated_entries =
      AnalysisCoordinator.handle_analysis_update(socket.assigns.entries, update_data)

    flash_message =
      case update_data.status do
        :complete -> "Analysis complete for entry!"
        :failed -> "Analysis failed for entry: #{update_data.data.error || "Unknown error"}"
        :processing -> "Analysis started for entry..."
        _ -> nil
      end

    socket =
      if flash_message do
        flash_type = if update_data.status == :failed, do: :error, else: :info
        put_flash(socket, flash_type, flash_message)
      else
        socket
      end

    {:noreply, assign(socket, entries: updated_entries)}
  end

  # Test-specific message handlers (simplified)
  def handle_info({:set_analyzing, analyzing}, socket),
    do: {:noreply, assign(socket, analyzing: analyzing)}

  def handle_info({:upload_error, _, _}, socket), do: {:noreply, socket}
  def handle_info({:database_error, _}, socket), do: {:noreply, socket}
  def handle_info({:entry_created, _}, socket), do: {:noreply, socket}

  def handle_info({:update_entries, entries}, socket),
    do: {:noreply, assign(socket, entries: entries)}

  def handle_info({:progress_update, progress}, socket),
    do: {:noreply, assign(socket, analysis_progress: progress)}

  def handle_info({:error, _}, socket), do: {:noreply, socket}

  # Async handlers
  @impl true
  def handle_async(:analyze_batch, {:ok, {:ok, analysis_results}}, socket) do
    updated_entries =
      AnalysisCoordinator.apply_analysis_results(socket.assigns.entries, analysis_results)

    {:noreply,
     socket
     |> assign(:analyzing, false)
     |> assign(:entries, updated_entries)
     |> put_flash(:info, "Batch analysis complete! Review results below.")}
  end

  def handle_async(:analyze_batch, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:analyzing, false)
     |> put_flash(:error, "Batch analysis failed. Please try again.")}
  end

  # Private helper functions

  defp generate_batch_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  defp handle_single_entry_save(socket, entry, entry_id) do
    try do
      save_results =
        case BatchProcessing.get_entry_with_images!(entry.id) do
          db_entry ->
            case BatchProcessing.save_entry_as_medicine(db_entry) do
              {:ok, medicine} -> [{:ok, medicine}]
              {:error, changeset} -> [{:error, entry.id, changeset}]
            end
        end

      handle_single_save_results(socket, save_results, entry_id)
    rescue
      e ->
        Logger.error("Error saving single entry: #{inspect(e)}")
        {:noreply, put_flash(socket, :error, "Failed to save entry: #{Exception.message(e)}")}
    end
  end

  defp handle_save_results(socket, save_results) do
    successes = Enum.count(save_results, &match?({:ok, _}, &1))
    failures = Enum.count(save_results, &match?({:error, _, _}, &1))

    message =
      if failures == 0 do
        "Successfully saved #{successes} medicines to your inventory!"
      else
        "Saved #{successes} medicines. #{failures} failed to save. Check logs for details."
      end

    flash_type = if failures > 0, do: :error, else: :info

    remaining_entries =
      if successes > 0 do
        Enum.reject(socket.assigns.entries, fn entry ->
          entry.approval_status == :approved
        end)
      else
        socket.assigns.entries
      end

    # Broadcast updates to other clients
    if successes > 0 do
      Phoenix.PubSub.broadcast(Medpack.PubSub, "medicines", {:batch_medicines_created, successes})
    end

    {:noreply,
     socket
     |> assign(:entries, remaining_entries)
     |> put_flash(flash_type, message)}
  end

  defp handle_single_save_results(socket, save_results, entry_id) do
    case save_results do
      [{:ok, medicine}] ->
        remaining_entries = Enum.reject(socket.assigns.entries, &(&1.id == entry_id))

        Phoenix.PubSub.broadcast(Medpack.PubSub, "medicines", {:batch_medicines_created, 1})

        {:noreply,
         socket
         |> assign(:entries, remaining_entries)
         |> put_flash(:info, "Successfully saved #{medicine.name} to your inventory!")}

      [{:error, _entry_id, changeset}] ->
        errors =
          changeset.errors
          |> Enum.map(fn {field, {message, _}} -> "#{field}: #{message}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Failed to save entry: #{errors}")}

      [] ->
        {:noreply, put_flash(socket, :error, "No entry to save - this might be a bug")}

      _ ->
        {:noreply, put_flash(socket, :error, "Unexpected error while saving entry")}
    end
  end
end
