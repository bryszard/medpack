defmodule MedpackWeb.CoreComponentsTest do
  use MedpackWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component
  import MedpackWeb.CoreComponents

  describe "topbar/1" do
    test "renders topbar with logo and navigation" do
      html = render_component(&topbar/1, current_page: :home)

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
      html = render_component(&topbar/1, current_page: :inventory)

      # Inventory button should be highlighted
      assert html =~ "bg-base-300"
      # Check that inventory icon is present
      assert html =~
               "M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
    end

    test "highlights medicine_show page when current_page is :medicine_show" do
      html = render_component(&topbar/1, current_page: :medicine_show)

      # Should also highlight inventory button for medicine show page
      assert html =~ "bg-base-300"
    end

    test "highlights add page when current_page is :add" do
      html = render_component(&topbar/1, current_page: :add)

      # Add button should be highlighted
      assert html =~ "bg-base-300"
      # Check that plus icon is present
      assert html =~ "M12 6v6m0 0v6m0-6h6m-6 0H6"
    end

    test "renders without highlighting when current_page is :home" do
      html = render_component(&topbar/1, current_page: :home)

      # No buttons should be highlighted for home page
      buttons_with_highlight = Regex.scan(~r/bg-base-300/, html)
      assert length(buttons_with_highlight) == 0
    end

    test "includes proper button styling and structure" do
      html = render_component(&topbar/1, current_page: :home)

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
      html =
        render_component(&flash/1, %{
          kind: :info,
          title: "Success",
          flash: %{"info" => "Operation completed successfully"}
        })

      # Should render flash content
      assert html =~ "Operation completed successfully"
      assert html =~ "alert-info"
    end

    test "renders error flash message" do
      html =
        render_component(&flash/1, %{
          kind: :error,
          title: "Error",
          flash: %{"error" => "Something went wrong"}
        })

      # Should render error flash content
      assert html =~ "Something went wrong"
      assert html =~ "alert-error"
    end

    test "handles empty flash" do
      html =
        render_component(&flash/1, %{
          kind: :info,
          flash: %{}
        })

      # Should handle empty flash gracefully
      assert is_binary(html)
    end

    test "renders with inner block" do
      assigns = %{
        kind: :info,
        flash: %{},
        inner_block: [
          %{__slot__: :inner_block, inner_block: fn _, _ -> "Custom flash message" end}
        ]
      }

      html = render_component(&flash/1, assigns)

      assert html =~ "Custom flash message"
    end
  end

  describe "icon/1" do
    test "renders heroicon with default outline style" do
      html = render_component(&icon/1, name: "hero-home")

      # Should render span with proper classes
      assert html =~ "<span"
      assert html =~ "hero-home"
      # Default size
      assert html =~ "size-4"
    end

    test "renders solid style icon" do
      html = render_component(&icon/1, name: "hero-home-solid")

      # Should render solid style
      assert html =~ "hero-home-solid"
    end

    test "renders mini style icon" do
      html = render_component(&icon/1, name: "hero-home-mini")

      # Should render mini style
      assert html =~ "hero-home-mini"
    end

    test "handles custom class" do
      html = render_component(&icon/1, name: "hero-home", class: "custom-class")

      # Should include custom class
      assert html =~ "custom-class"
    end
  end

  describe "input/1" do
    setup do
      # Create a simple form for testing inputs
      form = to_form(%{"name" => "Test Medicine"}, as: :test)
      field = form[:name]
      %{form: form, field: field}
    end

    test "renders text input with label", %{field: field} do
      html =
        render_component(&input/1, %{
          field: field,
          type: "text",
          label: "Medicine Name",
          required: true
        })

      # Should have input structure
      assert html =~ "input"
      assert html =~ "type=\"text\""
      assert html =~ "Medicine Name"
      assert html =~ "required"
    end

    test "renders select input with options", %{field: field} do
      html =
        render_component(&input/1, %{
          field: field,
          type: "select",
          label: "Dosage Form",
          options: [{"Tablet", "tablet"}, {"Capsule", "capsule"}]
        })

      # Should have select structure
      assert html =~ "<select"
      assert html =~ "Dosage Form"
      assert html =~ "Tablet"
      assert html =~ "Capsule"
      assert html =~ "value=\"tablet\""
      assert html =~ "value=\"capsule\""
    end

    test "renders textarea input", %{field: field} do
      html =
        render_component(&input/1, %{
          field: field,
          type: "textarea",
          label: "Notes"
        })

      # Should have textarea structure
      assert html =~ "<textarea"
      assert html =~ "Notes"
    end

    test "renders date input", %{field: field} do
      html =
        render_component(&input/1, %{
          field: field,
          type: "date",
          label: "Expiration Date"
        })

      # Should have date input
      assert html =~ "type=\"date\""
      assert html =~ "Expiration Date"
    end

    test "shows validation errors" do
      # Test with errors passed directly to the component
      html =
        render_component(&input/1, %{
          name: "test[name]",
          id: "test_name",
          type: "text",
          label: "Medicine Name",
          value: "",
          errors: ["can't be blank"]
        })

      # Should show error message and error styling
      assert html =~ "can&#39;t be blank"
      assert html =~ "input-error"
      assert html =~ "text-error"
    end
  end

  describe "button/1" do
    test "renders basic button" do
      assigns = %{
        inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Click me" end}]
      }

      html = render_component(&button/1, assigns)

      # Should have button structure
      assert html =~ "<button"
      assert html =~ "btn"
      assert html =~ "btn-primary btn-soft"
      assert html =~ "Click me"
    end

    test "renders button with custom attributes" do
      assigns = %{
        type: "submit",
        disabled: true,
        inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Submit" end}]
      }

      html = render_component(&button/1, assigns)

      # Should include custom attributes
      assert html =~ "type=\"submit\""
      assert html =~ "disabled"
      assert html =~ "Submit"
    end

    test "renders primary variant button" do
      assigns = %{
        variant: "primary",
        inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Primary" end}]
      }

      html = render_component(&button/1, assigns)

      # Should have primary styling
      assert html =~ "btn-primary"
      assert html =~ "Primary"
    end

    test "renders link button with navigation" do
      assigns = %{
        navigate: "/",
        inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Home" end}]
      }

      html = render_component(&button/1, assigns)

      # Should render as link
      assert html =~ "<a"
      assert html =~ "href=\"/\""
      assert html =~ "Home"
    end
  end

  describe "form validation and error handling" do
    test "handles form with no errors gracefully" do
      form = to_form(%{"name" => "Test Medicine"}, as: :medicine)
      field = form[:name]

      html =
        render_component(&input/1, %{
          field: field,
          type: "text",
          label: "Medicine Name"
        })

      # Should render without errors
      assert html =~ "Medicine Name"
      assert html =~ "value=\"Test Medicine\""
      refute html =~ "error"
    end

    test "handles complex form structures" do
      form = to_form(%{}, as: :form)
      field = form[:medicine]

      html =
        render_component(&input/1, %{
          field: field,
          type: "text",
          label: "Medicine Name"
        })

      # Should handle nested form structures
      assert html =~ "Medicine Name"
    end
  end

  describe "responsive design classes" do
    test "topbar includes responsive classes" do
      html = render_component(&topbar/1, current_page: :home)

      # Should have responsive design
      assert html =~ "flex"
      assert html =~ "items-center"
      assert html =~ "gap-4"
    end
  end

  describe "accessibility features" do
    test "inputs include proper labels and attributes" do
      form = to_form(%{}, as: :test)
      field = form[:name]

      html =
        render_component(&input/1, %{
          field: field,
          type: "text",
          label: "Medicine Name",
          required: true
        })

      # Should have accessibility attributes
      assert html =~ "required"
      # Should associate label with input
      assert html =~ "Medicine Name"
    end

    test "buttons include proper accessibility attributes" do
      assigns = %{
        "aria-label" => "Save medicine",
        inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Save" end}]
      }

      html = render_component(&button/1, assigns)

      # Should include aria-label
      assert html =~ "aria-label=\"Save medicine\""
    end
  end
end
