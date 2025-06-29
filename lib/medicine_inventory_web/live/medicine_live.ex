defmodule MedicineInventoryWeb.MedicineLive do
  use MedicineInventoryWeb, :live_view

  alias MedicineInventory.Medicines

  @impl true
  def mount(_params, _session, socket) do
    medicines = Medicines.list_medicines()

    {:ok,
     socket
     |> assign(:medicines, medicines)
     |> assign(:search_query, "")
     |> assign(:view_mode, :cards)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
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

  def handle_event("toggle_view", _params, socket) do
    new_view_mode = if socket.assigns.view_mode == :cards, do: :table, else: :cards
    {:noreply, assign(socket, view_mode: new_view_mode)}
  end

  @impl true
  def handle_info({:medicine_created, _medicine}, socket) do
    medicines = Medicines.list_medicines()
    {:noreply, assign(socket, medicines: medicines)}
  end
end
