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

  # Helper to ensure all entries have in-memory fields for UI compatibility
  def normalize_entry(entry) do
    # Check if this is a database entry with preloaded images
    {photos_uploaded, photo_paths, photo_web_paths, photo_entries} =
      case Map.get(entry, :images) do
        images when is_list(images) ->
          # Database entry with preloaded images
          sorted_images = Enum.sort_by(images, & &1.upload_order)

          photo_paths = Enum.map(sorted_images, & &1.s3_key)

          photo_web_paths =
            Enum.map(sorted_images, &Medpack.BatchProcessing.EntryImage.get_s3_url/1)

          photo_entries =
            Enum.map(sorted_images, fn image ->
              %{
                client_name: image.original_filename,
                client_size: image.file_size
              }
            end)

          {length(images), photo_paths, photo_web_paths, photo_entries}

        _ ->
          # In-memory entry or entry without images
          existing_photos = Map.get(entry, :photos_uploaded, 0)
          existing_paths = Map.get(entry, :photo_paths, [])
          existing_web_paths = Map.get(entry, :photo_web_paths, [])
          existing_entries = Map.get(entry, :photo_entries, [])

          {existing_photos, existing_paths, existing_web_paths, existing_entries}
      end

    entry
    |> Map.put(:photos_uploaded, photos_uploaded)
    |> Map.put(:photo_entries, photo_entries)
    |> Map.put(:photo_paths, photo_paths)
    |> Map.put(:photo_web_paths, photo_web_paths)
    |> Map.put_new(:ai_analysis_status, :pending)
    |> Map.put_new(:ai_results, %{})
    |> Map.put_new(:validation_errors, [])
    |> Map.put_new(:analysis_countdown, 0)
    |> Map.put_new(:analysis_timer_ref, nil)
  end

  @impl true
  def mount(_params, _session, socket) do
    # Fetch all unprocessed batch entries from the DB
    db_entries = BatchProcessing.list_unprocessed_entries()

    entries =
      if db_entries == [] do
        EntryManager.create_empty_entries(3)
      else
        # Map DB entries to add :number key for UI compatibility and normalize
        Enum.map(db_entries, fn entry ->
          entry
          |> Map.put(:number, entry.entry_number)
          |> normalize_entry()
        end)
      end

    # Configure individual uploads for each entry
    socket_with_uploads = UploadHandler.configure_uploads_for_entries(socket, entries)

    # Subscribe to analysis updates
    Phoenix.PubSub.subscribe(Medpack.PubSub, "batch_processing")

    {:ok,
     socket_with_uploads
     |> assign(:entries, entries)
     # batch_id is not unique per session anymore
     |> assign(:batch_id, nil)
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
    case BatchProcessing.get_entry(entry_id) do
      nil ->
        :ok

      entry ->
        # First clean up any associated images
        images = BatchProcessing.list_entry_images(entry_id)

        Enum.each(images, fn image ->
          Medpack.FileManager.delete_file(image.s3_key)
          BatchProcessing.delete_entry_image(image)
        end)

        # Then delete the entry
        BatchProcessing.delete_entry(entry)
    end

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

    socket_with_uploads = UploadHandler.configure_uploads_for_entries(socket, updated_entries)

    {:noreply,
     socket_with_uploads
     |> assign(entries: updated_entries)
     |> put_flash(:info, "Photo removed successfully")}
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

  # Add event handler to stop the countdown for an entry
  def handle_event("stop_countdown", %{"id" => entry_id}, socket) do
    updated_entries =
      MedpackWeb.BatchMedicineLive.AnalysisCoordinator.cancel_analysis_timer(
        socket.assigns.entries,
        entry_id
      )

    {:noreply, assign(socket, entries: updated_entries)}
  end

  # Add event handler to start the countdown for an entry
  def handle_event("start_countdown", %{"id" => entry_id}, socket) do
    # Always start a new countdown from 5 seconds
    send(self(), {:start_analysis_countdown, entry_id, 5})
    {:noreply, socket}
  end

  # Ensure analyze_now always triggers analysis, even if countdown is running or stopped
  def handle_event("analyze_now", %{"id" => entry_id}, socket) do
    # Cancel any running countdown for this entry
    updated_entries =
      MedpackWeb.BatchMedicineLive.AnalysisCoordinator.cancel_analysis_timer(
        socket.assigns.entries,
        entry_id
      )

    # Now trigger analysis
    case MedpackWeb.BatchMedicineLive.AnalysisCoordinator.trigger_entry_analysis(
           updated_entries,
           entry_id
         ) do
      {new_entries, {:info, message}} ->
        {:noreply,
         socket
         |> assign(entries: new_entries)
         |> put_flash(:info, message)}

      {new_entries, {:error, message}} ->
        {:noreply,
         socket
         |> assign(entries: new_entries)
         |> put_flash(:error, message)}

      {new_entries, nil} ->
        {:noreply, assign(socket, entries: new_entries)}
    end
  end

  # Ensure retry_analysis always works, even if countdown is running or stopped
  def handle_event("retry_analysis", %{"id" => entry_id}, socket) do
    # Cancel any running countdown for this entry
    updated_entries =
      MedpackWeb.BatchMedicineLive.AnalysisCoordinator.cancel_analysis_timer(
        socket.assigns.entries,
        entry_id
      )

    # Now retry analysis
    case MedpackWeb.BatchMedicineLive.AnalysisCoordinator.retry_entry_analysis(
           updated_entries,
           entry_id
         ) do
      {new_entries, flash_info} when is_tuple(flash_info) ->
        {flash_type, message} = flash_info

        {:noreply,
         socket
         |> assign(entries: new_entries)
         |> put_flash(flash_type, message)}

      {new_entries, _} ->
        {:noreply, assign(socket, entries: new_entries)}
    end
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

  def handle_event("save_single_entry", %{"id" => entry_id}, socket) do
    case Enum.find(
           socket.assigns.entries,
           &(EntryManager.normalize_entry_id(&1.id) == EntryManager.normalize_entry_id(entry_id))
         ) do
      nil ->
        {:noreply, put_flash(socket, :error, "Entry not found")}

      entry ->
        handle_single_entry_save(socket, entry, entry_id)
    end
  end

  # UI events
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
      |> Enum.map(&normalize_entry/1)

    socket_with_uploads = UploadHandler.configure_uploads_for_entries(socket, updated_entries)

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
        put_flash(socket_with_uploads, flash_type, flash_message)
      else
        socket_with_uploads
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
    do:
      {:noreply,
       UploadHandler.configure_uploads_for_entries(socket, entries) |> assign(entries: entries)}

  def handle_info({:progress_update, progress}, socket),
    do: {:noreply, assign(socket, analysis_progress: progress)}

  def handle_info({:error, _}, socket), do: {:noreply, socket}

  # Async handlers
  @impl true
  def handle_async(:analyze_batch, {:ok, {:ok, analysis_results}}, socket) do
    updated_entries =
      AnalysisCoordinator.apply_analysis_results(socket.assigns.entries, analysis_results)
      |> Enum.map(&normalize_entry/1)

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

      # After saving, normalize remaining entries
      handle_single_save_results(socket, save_results, entry_id)
    rescue
      e ->
        Logger.error("Error saving single entry: #{inspect(e)}")
        {:noreply, put_flash(socket, :error, "Failed to save entry: #{Exception.message(e)}")}
    end
  end

  defp handle_single_save_results(socket, save_results, entry_id) do
    case save_results do
      [{:ok, medicine}] ->
        remaining_entries =
          Enum.reject(socket.assigns.entries, &(&1.id == entry_id))
          |> Enum.map(&normalize_entry/1)

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
