defmodule MedpackWeb.PageController do
  use MedpackWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
