defmodule MedicineInventoryWeb.MedicineShowLive do
  use MedicineInventoryWeb, :live_view

  alias MedicineInventory.Medicines

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Medicines.get_medicine(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Medicine not found")
         |> redirect(to: ~p"/inventory")}

      medicine ->
        {:ok,
         socket
         |> assign(:medicine, medicine)
         |> assign(:page_title, medicine.name)}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
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
  def handle_info({:medicine_updated, medicine}, socket) do
    {:noreply, assign(socket, medicine: medicine)}
  end
end
