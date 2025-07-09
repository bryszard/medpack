defmodule MedpackWeb.PageControllerTest do
  use MedpackWeb.ConnCase

  describe "GET /" do
    test "displays the homepage with welcome content", %{conn: conn} do
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)

      # Check main welcome content
      assert response =~ "Welcome to Medpack"
      assert response =~ "Keep track of your medications with AI-powered photo recognition"
      assert response =~ "smart inventory management"
    end

    test "includes navigation links to main sections", %{conn: conn} do
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)

      # Check navigation links
      assert response =~ "href=\"/inventory\""
      assert response =~ "href=\"/add\""
      assert response =~ "View Inventory"
      assert response =~ "Add Medicines"
    end

    test "displays feature descriptions", %{conn: conn} do
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)

      # Check feature descriptions
      assert response =~ "Browse and search through your medicine collection"
      assert response =~ "Take photos of medicine bottles and let AI extract all the details"
      assert response =~ "Filter by expiration dates"
      assert response =~ "Smart search functionality"
    end

    test "includes proper page structure and styling", %{conn: conn} do
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)

      # Check essential CSS classes and structure
      assert response =~ "topbar"
      assert response =~ "hero"
      assert response =~ "card"
      assert response =~ "btn"

      # Check responsive design classes
      assert response =~ "grid"
      assert response =~ "md:grid-cols-2"
    end

    test "returns correct content type and status", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
    end
  end
end
