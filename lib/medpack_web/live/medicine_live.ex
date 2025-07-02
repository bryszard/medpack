defmodule MedpackWeb.MedicineLive do
  use MedpackWeb, :live_view

  alias Medpack.Medicines

  @impl true
  def mount(_params, _session, socket) do
    medicines = Medicines.list_medicines()

    {:ok,
     socket
     |> assign(:medicines, medicines)
     |> assign(:search_query, "")
     |> assign(:view_mode, :cards)
     |> assign(:filters, %{})
     |> assign(:show_filters, false)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    medicines = search_and_filter_medicines(query, socket.assigns.filters)

    {:noreply,
     socket
     |> assign(:medicines, medicines)
     |> assign(:search_query, query)}
  end

  def handle_event("toggle_view", _params, socket) do
    new_view_mode = if socket.assigns.view_mode == :cards, do: :table, else: :cards
    {:noreply, assign(socket, view_mode: new_view_mode)}
  end

  def handle_event("toggle_filters", _params, socket) do
    {:noreply, assign(socket, show_filters: not socket.assigns.show_filters)}
  end

  def handle_event("filter_change", %{"filter" => filter_params}, socket) do
    # Convert filter params to atoms and remove empty values
    filters =
      filter_params
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        if value != "" do
          Map.put(acc, String.to_atom(key), value)
        else
          acc
        end
      end)

    medicines = search_and_filter_medicines(socket.assigns.search_query, filters)

    {:noreply,
     socket
     |> assign(:medicines, medicines)
     |> assign(:filters, filters)}
  end

  def handle_event("clear_filters", _params, socket) do
    medicines = search_and_filter_medicines(socket.assigns.search_query, %{})

    {:noreply,
     socket
     |> assign(:medicines, medicines)
     |> assign(:filters, %{})}
  end

  @impl true
  def handle_info({:medicine_created, _medicine}, socket) do
    medicines = Medicines.list_medicines()
    {:noreply, assign(socket, medicines: medicines)}
  end

  # Helper function to handle both search and filtering
  defp search_and_filter_medicines(search_query, filters) do
    if search_query == "" and filters == %{} do
      Medicines.list_medicines()
    else
      Medicines.search_and_filter_medicines(search: search_query, filters: filters)
    end
  end

  # Helper function to get displayable photo URL
  def photo_url(photo_identifier) do
    Medpack.FileManager.get_photo_url(photo_identifier)
  end
end
