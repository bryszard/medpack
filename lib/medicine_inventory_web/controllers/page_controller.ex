defmodule MedicineInventoryWeb.PageController do
  use MedicineInventoryWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
