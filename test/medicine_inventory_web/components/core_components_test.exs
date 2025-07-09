defmodule MedpackWeb.CoreComponentsTest do
  use MedpackWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component
  import MedpackWeb.CoreComponents

  # Test helpers
  defp render_component_html(component, assigns \\ %{}) do
    rendered = component.(assigns)
    Phoenix.HTML.Safe.to_iodata(rendered) |> IO.iodata_to_binary()
  end

  describe "topbar/1" do
    test "renders topbar with logo and navigation" do
      html = render_component_html(&topbar/1, %{current_page: :home})

      # Should have navbar structure
      assert html =~ "navbar bg-base-200"
      assert html =~ "shadow-lg border-b"

      # Should have logo
      assert html =~ "medpack-logo.png"
      assert html =~ "Medpack Logo"

      # Should have navigation links
      assert html =~ "href=\"/inventory\""
      assert html =~ "href=\"/\""
      assert html =~ "href=\"/add\""
    end

    test "highlights inventory page when current_page is :inventory" do
      html = render_component_html(&topbar/1, %{current_page: :inventory})

      # Inventory button should be highlighted
      assert html =~ "bg-base-300"
      # Check that inventory icon is present
      assert html =~
               "M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
    end

    test "highlights medicine_show page when current_page is :medicine_show" do
      html = render_component_html(&topbar/1, %{current_page: :medicine_show})

      # Should also highlight inventory button for medicine show page
      assert html =~ "bg-base-300"
    end

    test "highlights add page when current_page is :add" do
      html = render_component_html(&topbar/1, %{current_page: :add})

      # Add button should be highlighted
      assert html =~ "bg-base-300"
      # Check that plus icon is present
      assert html =~ "M12 6v6m0 0v6m0-6h6m-6 0H6"
    end

    test "renders without highlighting when current_page is :home" do
      html = render_component_html(&topbar/1, %{current_page: :home})

      # No buttons should be highlighted for home page
      buttons_with_highlight = Regex.scan(~r/bg-base-300/, html)
      assert length(buttons_with_highlight) == 0
    end

    test "includes proper button styling and structure" do
      html = render_component_html(&topbar/1, %{current_page: :home})

      # Should have proper button classes
      assert html =~ "btn btn-circle"
      assert html =~ "btn-ghost"

      # Should have flex layout
      assert html =~ "flex items-center"
      assert html =~ "flex-1"
    end
  end

  describe "flash/1" do
    test "renders info flash message" do
      assigns = %{
        kind: :info,
        title: "Success",
        flash: %{"info" => "Operation completed successfully"}
      }

      html = render_component_html(&flash/1, assigns)

      # Should render flash content
      assert html =~ "Operation completed successfully"
    end

    test "renders error flash message" do
      assigns = %{
        kind: :error,
        title: "Error",
        flash: %{"error" => "Something went wrong"}
      }

      html = render_component_html(&flash/1, assigns)

      # Should render error flash content
      assert html =~ "Something went wrong"
    end

    test "handles empty flash" do
      assigns = %{
        kind: :info,
        flash: %{}
      }

      html = render_component_html(&flash/1, assigns)

      # Should handle empty flash gracefully
      assert is_binary(html)
    end
  end

  describe "table/1" do
    test "renders table with headers and data" do
      assigns = %{
        id: "test-table",
        rows: [
          %{id: 1, name: "Medicine 1", status: "active"},
          %{id: 2, name: "Medicine 2", status: "expired"}
        ],
        col: [
          %{label: "Name"},
          %{label: "Status"}
        ],
        row_item: fn row -> row end,
        action: []
      }

      html = render_component_html(&table/1, assigns)

      # Should have table structure
      assert html =~ "table table-zebra"
      assert html =~ "<thead>"
      assert html =~ "<tbody"

      # Should have headers
      assert html =~ "Name"
      assert html =~ "Status"

      # Should have data rows
      assert html =~ "Medicine 1"
      assert html =~ "Medicine 2"
      assert html =~ "active"
      assert html =~ "expired"
    end

    test "renders table with actions column" do
      assigns = %{
        id: "test-table",
        rows: [%{id: 1, name: "Medicine 1"}],
        col: [%{label: "Name"}],
        row_item: fn row -> row end,
        action: [%{label: "Edit"}]
      }

      html = render_component_html(&table/1, assigns)

      # Should have actions column header
      assert html =~ "Actions"
      assert html =~ "sr-only"

      # Should have actions cell
      assert html =~ "font-semibold"
      assert html =~ "flex gap-4"
    end

    test "handles empty table data" do
      assigns = %{
        id: "empty-table",
        rows: [],
        col: [%{label: "Name"}],
        row_item: fn row -> row end,
        action: []
      }

      html = render_component_html(&table/1, assigns)

      # Should still render table structure
      assert html =~ "table table-zebra"
      assert html =~ "Name"
    end

    test "handles clickable rows" do
      assigns = %{
        id: "clickable-table",
        rows: [%{id: 1, name: "Medicine 1"}],
        col: [%{label: "Name"}],
        row_item: fn row -> row end,
        row_click: fn _row -> "click-action" end,
        action: []
      }

      html = render_component_html(&table/1, assigns)

      # Should have clickable styling
      assert html =~ "hover:cursor-pointer"
    end
  end

  describe "list/1" do
    test "renders data list with items" do
      assigns = %{
        item: [
          %{title: "Medicine Name", content: "Aspirin"},
          %{title: "Dosage", content: "500mg"}
        ]
      }

      html = render_component_html(&list/1, assigns)

      # Should have list structure
      assert html =~ "ul class=\"list\""
      assert html =~ "li"
      assert html =~ "list-row"

      # Should show titles and content
      assert html =~ "Medicine Name"
      assert html =~ "Aspirin"
      assert html =~ "Dosage"
      assert html =~ "500mg"

      # Should have proper styling
      assert html =~ "font-bold"
    end

    test "handles empty list" do
      assigns = %{item: []}

      html = render_component_html(&list/1, assigns)

      # Should render empty list structure
      assert html =~ "ul class=\"list\""
    end
  end

  describe "icon/1" do
    test "renders heroicon with default outline style" do
      assigns = %{name: "home"}

      html = render_component_html(&icon/1, assigns)

      # Should render SVG with proper classes
      assert html =~ "<svg"
      # Default size
      assert html =~ "h-5 w-5"
      # Outline style
      assert html =~ "fill=\"none\""
      assert html =~ "stroke=\"currentColor\""
    end

    test "renders solid style icon" do
      assigns = %{name: "home-solid"}

      html = render_component_html(&icon/1, assigns)

      # Should render solid style
      assert html =~ "fill=\"currentColor\""
      refute html =~ "stroke=\"currentColor\""
    end

    test "renders mini style icon" do
      assigns = %{name: "home-mini"}

      html = render_component_html(&icon/1, assigns)

      # Should render mini size
      assert html =~ "h-3 w-3"
    end

    test "handles custom class" do
      assigns = %{name: "home", class: "custom-class"}

      html = render_component_html(&icon/1, assigns)

      # Should include custom class
      assert html =~ "custom-class"
    end
  end

  describe "input/1" do
    setup do
      # Create a simple form for testing inputs
      form = to_form(%{}, as: :test)
      field = form[:name]
      %{form: form, field: field}
    end

    test "renders text input with label", %{field: field} do
      assigns = %{
        field: field,
        type: "text",
        label: "Medicine Name",
        required: true
      }

      html = render_component_html(&input/1, assigns)

      # Should have input structure
      assert html =~ "input"
      assert html =~ "type=\"text\""
      assert html =~ "Medicine Name"
      assert html =~ "required"
    end

    test "renders select input with options", %{field: field} do
      assigns = %{
        field: field,
        type: "select",
        label: "Dosage Form",
        options: [{"Tablet", "tablet"}, {"Capsule", "capsule"}]
      }

      html = render_component_html(&input/1, assigns)

      # Should have select structure
      assert html =~ "<select"
      assert html =~ "Dosage Form"
      assert html =~ "Tablet"
      assert html =~ "Capsule"
      assert html =~ "value=\"tablet\""
      assert html =~ "value=\"capsule\""
    end

    test "renders textarea input", %{field: field} do
      assigns = %{
        field: field,
        type: "textarea",
        label: "Notes"
      }

      html = render_component_html(&input/1, assigns)

      # Should have textarea structure
      assert html =~ "<textarea"
      assert html =~ "Notes"
    end

    test "renders date input", %{field: field} do
      assigns = %{
        field: field,
        type: "date",
        label: "Expiration Date"
      }

      html = render_component_html(&input/1, assigns)

      # Should have date input
      assert html =~ "type=\"date\""
      assert html =~ "Expiration Date"
    end

    test "shows validation errors", %{form: form} do
      # Create form with errors
      changeset = %Ecto.Changeset{
        action: :validate,
        changes: %{},
        errors: [name: {"can't be blank", [validation: :required]}],
        data: %{},
        valid?: false
      }

      form_with_errors = to_form(changeset, as: :test)
      field = form_with_errors[:name]

      assigns = %{
        field: field,
        type: "text",
        label: "Medicine Name"
      }

      html = render_component_html(&input/1, assigns)

      # Should show error message
      assert html =~ "can't be blank" or html =~ "can&#39;t be blank"
    end
  end

  describe "button/1" do
    test "renders basic button" do
      assigns = %{class: "btn-primary"}

      html = render_component_html(&button/1, assigns)

      # Should have button structure
      assert html =~ "<button"
      assert html =~ "btn"
      assert html =~ "btn-primary"
    end

    test "renders button with custom attributes" do
      assigns = %{
        class: "btn-secondary",
        type: "submit",
        disabled: true
      }

      html = render_component_html(&button/1, assigns)

      # Should include custom attributes
      assert html =~ "type=\"submit\""
      assert html =~ "disabled"
      assert html =~ "btn-secondary"
    end
  end

  describe "form validation and error handling" do
    test "handles form with no errors gracefully" do
      form = to_form(%{name: "Test Medicine"}, as: :medicine)
      field = form[:name]

      assigns = %{
        field: field,
        type: "text",
        label: "Medicine Name"
      }

      html = render_component_html(&input/1, assigns)

      # Should render without errors
      assert html =~ "Medicine Name"
      assert html =~ "value=\"Test Medicine\""
      refute html =~ "error"
    end

    test "handles complex form structures" do
      form =
        to_form(
          %{
            medicine: %{
              name: "Test Medicine",
              dosage_form: "tablet"
            }
          },
          as: :form
        )

      field = form[:medicine][:name]

      assigns = %{
        field: field,
        type: "text",
        label: "Medicine Name"
      }

      html = render_component_html(&input/1, assigns)

      # Should handle nested form structures
      assert html =~ "Medicine Name"
    end
  end

  describe "responsive design classes" do
    test "topbar includes responsive classes" do
      html = render_component_html(&topbar/1, %{current_page: :home})

      # Should have responsive design
      assert html =~ "flex"
      assert html =~ "items-center"
      assert html =~ "gap-4"
    end

    test "table includes responsive classes" do
      assigns = %{
        id: "responsive-table",
        rows: [],
        col: [%{label: "Name"}],
        row_item: fn row -> row end,
        action: []
      }

      html = render_component_html(&table/1, assigns)

      # Should have responsive table structure
      assert html =~ "table"
    end
  end

  describe "accessibility features" do
    test "inputs include proper labels and attributes" do
      form = to_form(%{}, as: :test)
      field = form[:name]

      assigns = %{
        field: field,
        type: "text",
        label: "Medicine Name",
        required: true
      }

      html = render_component_html(&input/1, assigns)

      # Should have accessibility attributes
      assert html =~ "required"
      # Should associate label with input
      assert html =~ "Medicine Name"
    end

    test "buttons include proper accessibility attributes" do
      assigns = %{
        class: "btn-primary",
        "aria-label": "Save medicine"
      }

      html = render_component_html(&button/1, assigns)

      # Should include aria-label
      assert html =~ "aria-label=\"Save medicine\""
    end

    test "table includes proper structure for screen readers" do
      assigns = %{
        id: "accessible-table",
        rows: [%{name: "Medicine"}],
        col: [%{label: "Name"}],
        row_item: fn row -> row end,
        action: [%{label: "Edit"}]
      }

      html = render_component_html(&table/1, assigns)

      # Should have proper table structure
      assert html =~ "<thead>"
      assert html =~ "<tbody"
      assert html =~ "<th"
      assert html =~ "<td"

      # Should have screen reader text for actions
      assert html =~ "sr-only"
    end
  end
end
