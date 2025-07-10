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
      assert response =~
               "Browse your current medicine collection, search by name, and check expiration dates"

      assert response =~
               "Take photos of medicine bottles and let AI extract all the details automatically"

      assert response =~ "Automatically extract medicine details from photos"
      assert response =~ "Never miss expiration dates with smart reminders"
    end

    test "returns correct content type and status", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
    end
  end
end
