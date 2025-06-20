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
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
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
    photo_path = consume_uploaded_photo(socket)
    medicine_params = Map.put(medicine_params, "photo_path", photo_path)

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
    {:noreply, assign(socket, show_form: not socket.assigns.show_form)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  @impl true
  def handle_info({:medicine_created, _medicine}, socket) do
    medicines = Medicines.list_medicines()
    {:noreply, assign(socket, medicines: medicines)}
  end

  defp consume_uploaded_photo(socket) do
    consume_uploaded_entries(socket, :photo, fn %{path: path}, _entry ->
      dest =
        Path.join([:code.priv_dir(:medicine_inventory), "static", "uploads", Path.basename(path)])

      File.cp!(path, dest)
      {:ok, "/uploads/" <> Path.basename(path)}
    end)
    |> case do
      [photo_path] -> photo_path
      [] -> nil
    end
  end
end
