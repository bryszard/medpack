defmodule MedpackWeb.BatchEntryComponents do
  @moduledoc """
  Components for batch medicine entry processing.

  This module contains focused components extracted from the large
  BatchMedicineLive template to improve maintainability and reusability.
  """

  use MedpackWeb, :html
  alias Medpack.BatchProcessing.Entry

  @doc """
  Renders the cards grid view for detailed entry management.
  """
  def entry_cards_grid(assigns) do
    ~H"""
    <%= if @analyzing do %>
      <.analysis_progress_alert progress={@analysis_progress} />
    <% end %>

    <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
      <%= for entry <- @entries do %>
        <.entry_card entry={entry} uploads={@uploads} selected_for_edit={@selected_for_edit} />
      <% end %>

      <.ghost_entry_card />
    </div>
    """
  end

  @doc """
  Renders an individual entry card.
  """
  def entry_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl shadow-lg border border-base-200 overflow-hidden hover:shadow-xl transition duration-300">
      <.entry_header entry={@entry} />

      <div class="p-6">
        <.photo_upload_section entry={@entry} uploads={@uploads} />
        <.status_display_section entry={@entry} />
        <%= if @entry.ai_analysis_status in [:processing, :failed, :complete] do %>
          <.analysis_results_section entry={@entry} selected_for_edit={@selected_for_edit} />
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders the entry card header with title and remove button.
  """
  def entry_header(assigns) do
    # Try to get the medicine name from AI results if available
    medicine_name =
      case Map.get(assigns.entry, :ai_results) do
        %{"name" => name} when is_binary(name) and name != "" -> name
        _ -> nil
      end

    assigns = assign(assigns, :medicine_name, medicine_name)

    ~H"""
    <div class="bg-base-100 px-6 py-4 border-b border-base-200 flex justify-between items-center">
      <h3 class="text-lg font-bold text-base-900">
        <%= if @medicine_name do %>
          {@medicine_name}
        <% else %>
          Medicine Entry
        <% end %>
      </h3>
      <button
        phx-click="remove_entry"
        phx-value-id={@entry.id}
        class="text-error hover:text-error-content p-1 rounded-lg hover:bg-error/10 transition duration-200"
      >
        <.icon name="hero-x-mark" class="h-5 w-5" />
      </button>
    </div>
    """
  end

  @doc """
  Renders the photo upload section for an entry.
  """
  def photo_upload_section(assigns) do
    photos_count = Map.get(assigns.entry, :photos_uploaded, 0)

    assigns = assign(assigns, :photos_count, photos_count)

    ~H"""
    <div class="mb-6">
      <div class="flex justify-between items-center mb-3">
        <h4 class="font-semibold text-base-900">
          Photos ({@photos_count}/3):
        </h4>
      </div>

      <.uploaded_photos_display entry={@entry} />
      <.upload_previews_display entry={@entry} uploads={@uploads} />

      <%= if @photos_count < 3 do %>
        <.upload_form entry={@entry} uploads={@uploads} />
      <% end %>
    </div>
    """
  end

  @doc """
  Renders uploaded photos display.
  """
  def uploaded_photos_display(assigns) do
    photos_count = Map.get(assigns.entry, :photos_uploaded, 0)
    photo_web_paths = Map.get(assigns.entry, :photo_web_paths, [])

    assigns =
      assigns |> assign(:photos_count, photos_count) |> assign(:photo_web_paths, photo_web_paths)

    ~H"""
    <%= if @photos_count > 0 and @photo_web_paths != [] do %>
      <div class="grid grid-cols-3 gap-2 mb-4">
        <%= for {photo_web_path, index} <- Enum.with_index(@photo_web_paths) do %>
          <div class="relative">
            <img
              src={photo_web_path}
              alt={"Uploaded medicine photo #{index + 1}"}
              class="w-full h-24 object-cover rounded-lg border-2 border-base-300 cursor-pointer hover:opacity-80 transition-opacity"
              phx-click="enlarge_photo"
              phx-value-entry_id={@entry.id}
              phx-value-photo_index={index}
            />
            <button
              phx-click="remove_photo"
              phx-value-id={@entry.id}
              phx-value-photo_index={index}
              class="absolute -top-2 -right-2 btn btn-error btn-xs rounded-full w-6 h-6 min-h-0 p-0"
            >
              ✕
            </button>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  @doc """
  Renders upload previews for files being uploaded.
  """
  def upload_previews_display(assigns) do
    upload_entries = get_upload_entries_for_entry(assigns.entry, assigns.uploads)

    assigns = assigns |> assign(:upload_entries, upload_entries)

    ~H"""
    <%= for entry_upload <- @upload_entries do %>
      <div class="flex items-center space-x-4 bg-base-100 p-4 rounded-lg border border-base-200 mb-3">
        <div class="flex-shrink-0">
          <.live_img_preview
            entry={entry_upload}
            class="h-20 w-20 object-cover rounded-lg border-2 border-base-300"
          />
        </div>
        <div class="flex-1 min-w-0">
          <p class="text-lg font-semibold text-base-900 truncate">
            {entry_upload.client_name}
          </p>
          <p class="text-base-600">
            {Float.round(entry_upload.client_size / 1_048_576, 2)} MB
          </p>
          <div class="w-full bg-base-200 rounded-full h-3 mt-2">
            <div
              class="bg-base-500 h-3 rounded-full transition-all duration-300"
              style={"width: #{entry_upload.progress}%"}
            >
            </div>
          </div>
        </div>
        <button
          type="button"
          phx-click="cancel_upload"
          phx-value-ref={entry_upload.ref}
          class="text-error hover:text-error-content p-2 rounded-lg hover:bg-error/10 transition duration-200"
        >
          <.icon name="hero-x-mark" class="h-6 w-6" />
        </button>
      </div>
    <% end %>
    """
  end

  @doc """
  Renders the upload form for new photos.
  """
  def upload_form(assigns) do
    upload_key = String.to_atom("entry_#{assigns.entry.id}_photos")
    remaining_slots = 3 - Map.get(assigns.entry, :photos_uploaded, 0)

    assigns =
      assigns |> assign(:upload_key, upload_key) |> assign(:remaining_slots, remaining_slots)

    ~H"""
    <form phx-change="validate" phx-submit="upload" id={"upload-form-#{@entry.id}"}>
      <div
        phx-drop-target={@upload_key}
        class="border-2 border-dashed border-base-300 rounded-lg p-6 text-center hover:border-base-400 transition duration-200"
      >
        <div class="text-base-600 mb-2">
          <.icon name="hero-photo" class="mx-auto h-8 w-8" />
        </div>
        <div class="cursor-pointer" onclick="this.querySelector('input[type=file]').click()">
          <span class="text-base-700 font-semibold hover:text-base-600">
            📸 Add photo ({@remaining_slots} remaining)
          </span>
          <%= if @uploads[@upload_key] do %>
            <.live_file_input
              upload={@uploads[@upload_key]}
              id={"file-input-#{@entry.id}"}
              class="sr-only"
            />
          <% else %>
            <span class="text-error">Upload config not ready</span>
          <% end %>
        </div>
        <p class="text-base-500 text-sm mt-1">JPG, PNG up to 10MB each</p>
      </div>
    </form>
    """
  end

  @doc """
  Renders the status display section with countdown timer.
  """
  def status_display_section(assigns) do
    ~H"""
    <div class="mb-4">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-2">
          <span class="text-2xl">{Entry.status_icon(@entry)}</span>
          <span class="text-base-900 font-semibold">
            {Entry.status_text(@entry)}
          </span>
        </div>

        <.analysis_countdown_display entry={@entry} />
      </div>
    </div>
    """
  end

  @doc """
  Renders analysis countdown timer or manual trigger button.
  """
  def analysis_countdown_display(assigns) do
    countdown = Map.get(assigns.entry, :analysis_countdown, 0)
    photos_count = Map.get(assigns.entry, :photos_uploaded, 0)
    timer_active = countdown > 0
    analysis_status = Map.get(assigns.entry, :ai_analysis_status, :pending)

    assigns =
      assigns
      |> assign(:countdown, countdown)
      |> assign(:photos_count, photos_count)
      |> assign(:timer_active, timer_active)
      |> assign(:analysis_status, analysis_status)

    ~H"""
    <%= cond do %>
      <% @timer_active -> %>
        <div class="flex items-center space-x-3">
          <.countdown_timer countdown={@countdown} />
          <div class="text-center">
            <p class="text-xs text-base-600 mb-1">Analysis starts in</p>
            <button phx-click="analyze_now" phx-value-id={@entry.id} class="btn btn-primary btn-xs">
              Analyze Now
            </button>
            <button
              phx-click="stop_countdown"
              phx-value-id={@entry.id}
              class="btn btn-warning btn-xs ml-2"
            >
              Stop Countdown
            </button>
          </div>
        </div>
      <% @analysis_status == :pending and @photos_count > 0 -> %>
        <div class="flex justify-end space-x-2">
          <button phx-click="analyze_now" phx-value-id={@entry.id} class="btn btn-primary btn-sm">
            🤖 Analyze Now
          </button>
        </div>
      <% true -> %>
        <div></div>
    <% end %>
    """
  end

  @doc """
  Renders a circular countdown timer with smooth animation.
  """
  def countdown_timer(assigns) do
    total = 4.0
    countdown = assigns.countdown - 1
    progress = countdown / total * 100

    # SVG circle parameters
    radius = 16
    circumference = 2 * :math.pi() * radius
    dashoffset = circumference * (progress / 100)

    assigns =
      assigns
      |> assign(:progress, progress)
      |> assign(:radius, radius)
      |> assign(:circumference, circumference)
      |> assign(:dashoffset, dashoffset)

    ~H"""
    <div class="relative">
      <svg class="w-12 h-12" viewBox="0 0 36 36">
        <!-- Background Circle -->
        <circle
          cx="18" cy="18" r={@radius}
          fill="none"
          stroke-width="3"
          class="text-base-200"
          stroke="currentColor"
        />
        <!-- Foreground Progress Circle -->
        <circle
          cx="18" cy="18" r={@radius}
          fill="none"
          stroke-width="3"
          class="text-blue-500"
          stroke="currentColor"
          style={
            "stroke-dasharray: #{@circumference}; " <>
            "stroke-dashoffset: #{@dashoffset}; " <>
            "transform: rotate(-90deg); " <>
            "transform-origin: 50% 50%; " <>
            "transition: stroke-dashoffset 1s linear;"
          }
        />
      </svg>
      <div class="absolute inset-0 flex items-center justify-center">
        <span class="text-sm font-bold text-base-600">
          {@countdown}
        </span>
      </div>
    </div>
    """
  end

  @doc """
  Renders the AI analysis results section.
  """
  def analysis_results_section(assigns) do
    entry_id_normalized = normalize_entry_id(assigns.entry.id)
    selected_id_normalized = normalize_entry_id(assigns.selected_for_edit)
    is_editing = entry_id_normalized == selected_id_normalized
    assigns = assign(assigns, :is_editing, is_editing)

    ~H"""
    <div class="bg-base-100 rounded-lg p-4 border border-base-200">
      <h4 class="font-semibold text-base-900 mb-2">🤖 AI Analysis Results:</h4>

      <%= if @is_editing do %>
        <.entry_edit_form entry={@entry} />
      <% else %>
        <%= case @entry.ai_analysis_status do %>
          <% :processing -> %>
            <.processing_indicator />
          <% :failed -> %>
            <.failed_analysis_display entry={@entry} />
          <% :complete -> %>
            <.complete_analysis_display entry={@entry} selected_for_edit={@selected_for_edit} />
        <% end %>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders processing indicator.
  """
  def processing_indicator(assigns) do
    ~H"""
    <div class="flex items-center space-x-2">
      <div class="loading loading-spinner loading-sm"></div>
      <span class="text-base-600">Analyzing photos...</span>
    </div>
    """
  end

  @doc """
  Renders failed analysis display.
  """
  def failed_analysis_display(assigns) do
    photos_count = Map.get(assigns.entry, :photos_uploaded, 0)
    assigns = assign(assigns, :photos_count, photos_count)

    ~H"""
    <div class="alert alert-error flex flex-col items-center justify-center">
      <span>❌ Analysis failed. Please try again or check your photos.</span>
      <%= if @photos_count > 0 do %>
        <button phx-click="retry_analysis" phx-value-id={@entry.id} class="btn btn-error mt-2">
          🔄 Retry
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders complete analysis results.
  """
  def complete_analysis_display(assigns) do
    photos_count = Map.get(assigns.entry, :photos_uploaded, 0)
    assigns = assign(assigns, :photos_count, photos_count)

    ~H"""
    <div class="space-y-3">
      <!-- Photo Analysis Summary -->
      <div class="bg-green-50 border-l-4 border-green-400 p-3 rounded-lg">
        <p class="text-green-700 text-sm">
          ✅ Analysis completed using {@photos_count} photo(s)
        </p>
      </div>

      <.field_extraction_results entry={@entry} />
      <.entry_actions entry={@entry} selected_for_edit={@selected_for_edit} />
    </div>
    """
  end

  @doc """
  Renders field extraction results.
  """
  def field_extraction_results(assigns) do
    ~H"""
    <!-- Essential Fields -->
    <div class="bg-base-100 rounded-lg p-3 border-l-4 border-green-500">
      <h5 class="font-semibold text-green-800 mb-2">✅ Essential Information</h5>
      <div class="grid grid-cols-1 gap-2 text-sm">
        <.field_status_row entry={@entry} field_key="name" field_name="Medicine Name" />
        <.field_status_row entry={@entry} field_key="dosage_form" field_name="Dosage Form" />
        <.field_status_row
          entry={@entry}
          field_key="active_ingredient"
          field_name="Active Ingredient"
        />
        <.field_status_row entry={@entry} field_key="strength_value" field_name="Strength Value" />
        <.field_status_row entry={@entry} field_key="strength_unit" field_name="Strength Unit" />
        <.field_status_row entry={@entry} field_key="container_type" field_name="Container Type" />
        <.field_status_row entry={@entry} field_key="total_quantity" field_name="Total Quantity" />
        <.field_status_row entry={@entry} field_key="quantity_unit" field_name="Quantity Unit" />
      </div>
    </div>

    <!-- Optional Fields -->
    <div class="bg-base-100 rounded-lg p-3 border-l-4 border-blue-500">
      <h5 class="font-semibold text-blue-800 mb-2">📋 Additional Information</h5>
      <div class="grid grid-cols-1 gap-2 text-sm">
        <.field_status_row entry={@entry} field_key="brand_name" field_name="Brand Name" />
        <.field_status_row entry={@entry} field_key="manufacturer" field_name="Manufacturer" />
        <.field_status_row entry={@entry} field_key="expiration_date" field_name="Expiration Date" />
        <.field_status_row
          entry={@entry}
          field_key="remaining_quantity"
          field_name="Remaining Quantity"
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a field status row.
  """
  def field_status_row(assigns) do
    field_status = Entry.field_status(assigns.entry, assigns.field_key)
    assigns = assign(assigns, :field_status, field_status)

    ~H"""
    <div class="flex items-center justify-between">
      <span class="text-gray-600">{@field_name}:</span>
      <%= case @field_status do %>
        <% :missing -> %>
          <span class="text-red-600 text-xs">❌ Not detected</span>
        <% {:present, value} -> %>
          <span class="text-green-700 font-medium">✅ {value}</span>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders entry actions (approve, edit, reject, save).
  """
  def entry_actions(assigns) do
    entry_id_normalized = normalize_entry_id(assigns.entry.id)
    selected_id_normalized = normalize_entry_id(assigns.selected_for_edit)
    is_editing = entry_id_normalized == selected_id_normalized

    assigns = assign(assigns, :is_editing, is_editing)

    ~H"""
    <%= if @is_editing do %>
      <.entry_edit_form entry={@entry} />
    <% else %>
      <div class="card-actions justify-center mt-4">
        <button phx-click="save_single_entry" phx-value-id={@entry.id} class="btn btn-primary">
          💾 Save
        </button>
        <button phx-click="edit_entry" phx-value-id={@entry.id} class="btn btn-info">
          ✏️ Edit
        </button>
      </div>
    <% end %>
    """
  end

  @doc """
  Renders batch action buttons.
  """
  def batch_actions(assigns) do
    has_photos = Enum.any?(assigns.entries, &(Map.get(&1, :photos_uploaded, 0) > 0))
    has_complete = Enum.any?(assigns.entries, &(&1.ai_analysis_status == :complete))

    assigns =
      assigns
      |> assign(:has_photos, has_photos)
      |> assign(:has_complete, has_complete)

    ~H"""
    <%= if @has_photos do %>
      <div class="flex flex-wrap justify-center gap-4 mt-8">
        <button
          phx-click="analyze_all"
          disabled={@analyzing}
          class={
            if @analyzing,
              do: "btn btn-primary btn-lg loading",
              else: "btn btn-primary btn-lg"
          }
        >
          {if @analyzing, do: "🔍 Analyzing...", else: "🤖 Analyze All Photos"}
        </button>
      </div>
    <% end %>
    """
  end

  # Helper functions (matching LiveView helpers)

  defp get_upload_entries_for_entry(entry, uploads) do
    upload_key = String.to_atom("entry_#{entry.id}_photos")
    upload_config = Map.get(uploads, upload_key, %{entries: []})
    upload_config.entries
  end

  defp normalize_entry_id(nil), do: nil
  defp normalize_entry_id(entry_id) when is_integer(entry_id), do: entry_id

  defp normalize_entry_id(entry_id) when is_binary(entry_id) do
    # Check if it's a UUID format (36 characters with dashes)
    if String.length(entry_id) == 36 and String.contains?(entry_id, "-") do
      # It's a UUID, return as-is
      entry_id
    else
      # Try to parse as integer for legacy IDs
      case Integer.parse(entry_id) do
        {id, _} -> id
        :error -> entry_id
      end
    end
  end

  defp normalize_entry_id(entry_id), do: entry_id

  # Component-specific functions

  @doc """
  Renders a ghost entry card for adding new entries.
  """
  def ghost_entry_card(assigns) do
    ~H"""
    <div
      class="flex flex-col justify-center items-center bg-base-100 rounded-xl shadow-lg border-2 border-dashed border-base-300 overflow-hidden hover:shadow-xl transition duration-300 cursor-pointer hover:border-base-400"
      phx-click="add_ghost_entry"
    >
      <div class="p-12 text-center">
        <div class="text-6xl text-base-400 mb-4">➕</div>
        <h3 class="text-xl font-bold text-base-600 mb-2">Add New Medicine</h3>
        <p class="text-base-500">Click to add a new medicine entry</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders analysis progress alert.
  """
  def analysis_progress_alert(assigns) do
    ~H"""
    <div class="alert alert-info mb-8">
      <div class="flex items-center gap-4">
        <span class="loading loading-spinner loading-md"></span>
        <div>
          <h3 class="font-bold">🔍 AI Analysis in Progress...</h3>
          <div class="mt-2">
            <progress class="progress progress-info w-full" value={@progress} max="100"></progress>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Renders a comprehensive edit form for medicine entry data.
  defp entry_edit_form(assigns) do
    # Create form data from entry's AI results
    medicine_data = Map.get(assigns.entry, :ai_results, %{})

    # Only include fields shown in analysis details
    form_data = %{
      "name" => Map.get(medicine_data, "name", ""),
      "dosage_form" => Map.get(medicine_data, "dosage_form", ""),
      "active_ingredient" => Map.get(medicine_data, "active_ingredient", ""),
      "strength_value" => to_string(Map.get(medicine_data, "strength_value", "")),
      "strength_unit" => Map.get(medicine_data, "strength_unit", ""),
      "container_type" => Map.get(medicine_data, "container_type", ""),
      "total_quantity" => to_string(Map.get(medicine_data, "total_quantity", "")),
      "quantity_unit" => Map.get(medicine_data, "quantity_unit", ""),
      "brand_name" => Map.get(medicine_data, "brand_name", ""),
      "manufacturer" => Map.get(medicine_data, "manufacturer", ""),
      "expiration_date" =>
        format_expiration_for_input(Map.get(medicine_data, "expiration_date", "")),
      "remaining_quantity" => to_string(Map.get(medicine_data, "remaining_quantity", ""))
    }

    assigns = assign(assigns, :form_data, form_data)

    ~H"""
    <div class="card bg-base-100 border-2 border-info mt-4">
      <div class="card-body">
        <form
          id={"edit-form-#{@entry.id}"}
          phx-submit="save_entry_edit"
          phx-change="validate_entry_edit"
          class="space-y-6"
        >
          <input type="hidden" name="entry_id" value={@entry.id} />

    <!-- Essential Information -->
          <div>
            <h3 class="text-lg font-bold text-green-800 mb-3">✅ Essential Information</h3>
            <div class="space-y-3">
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Medicine Name *</span>
                </label>
                <input
                  type="text"
                  name="medicine[name]"
                  value={@form_data["name"]}
                  class="input input-bordered"
                  required
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Dosage Form *</span>
                </label>
                <input
                  type="text"
                  name="medicine[dosage_form]"
                  value={@form_data["dosage_form"]}
                  class="input input-bordered"
                  required
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Active Ingredient</span>
                </label>
                <input
                  type="text"
                  name="medicine[active_ingredient]"
                  value={@form_data["active_ingredient"]}
                  class="input input-bordered"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Strength Value</span>
                </label>
                <input
                  type="number"
                  step="0.01"
                  name="medicine[strength_value]"
                  value={@form_data["strength_value"]}
                  class="input input-bordered"
                  placeholder="e.g. 500"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Strength Unit</span>
                </label>
                <input
                  type="text"
                  name="medicine[strength_unit]"
                  value={@form_data["strength_unit"]}
                  class="input input-bordered"
                  placeholder="e.g. mg"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Strength Unit</span>
                </label>
                <input
                  type="text"
                  name="medicine[strength_unit]"
                  value={@form_data["strength_unit"]}
                  class="input input-bordered"
                  placeholder="e.g. mg"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Container Type</span>
                </label>
                <select name="medicine[container_type]" class="select select-bordered">
                  <option value="bottle" selected={@form_data["container_type"] == "bottle"}>
                    Bottle
                  </option>
                  <option value="box" selected={@form_data["container_type"] == "box"}>Box</option>
                  <option value="tube" selected={@form_data["container_type"] == "tube"}>Tube</option>
                  <option value="vial" selected={@form_data["container_type"] == "vial"}>Vial</option>
                  <option value="inhaler" selected={@form_data["container_type"] == "inhaler"}>
                    Inhaler
                  </option>
                  <option
                    value="blister_pack"
                    selected={@form_data["container_type"] == "blister_pack"}
                  >
                    Blister Pack
                  </option>
                  <option value="sachet" selected={@form_data["container_type"] == "sachet"}>
                    Sachet
                  </option>
                  <option value="ampoule" selected={@form_data["container_type"] == "ampoule"}>
                    Ampoule
                  </option>
                </select>
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Total Quantity</span>
                </label>
                <input
                  type="number"
                  step="0.01"
                  name="medicine[total_quantity]"
                  value={@form_data["total_quantity"]}
                  class="input input-bordered"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Quantity Unit</span>
                </label>
                <input
                  type="text"
                  name="medicine[quantity_unit]"
                  value={@form_data["quantity_unit"]}
                  class="input input-bordered"
                  placeholder="e.g. tablets, ml, capsules"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Quantity Unit</span>
                </label>
                <input
                  type="text"
                  name="medicine[quantity_unit]"
                  value={@form_data["quantity_unit"]}
                  class="input input-bordered"
                  placeholder="e.g. mg"
                />
              </div>
            </div>
          </div>

    <!-- Additional Information -->
          <div>
            <h3 class="text-lg font-bold text-blue-800 mb-3">📋 Additional Information</h3>
            <div class="space-y-3">
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Brand Name</span>
                </label>
                <input
                  type="text"
                  name="medicine[brand_name]"
                  value={@form_data["brand_name"]}
                  class="input input-bordered"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Manufacturer</span>
                </label>
                <input
                  type="text"
                  name="medicine[manufacturer]"
                  value={@form_data["manufacturer"]}
                  class="input input-bordered"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Expiration Date</span>
                </label>
                <input
                  type="month"
                  name="medicine[expiration_date]"
                  value={@form_data["expiration_date"]}
                  class="input input-bordered"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Remaining Quantity</span>
                </label>
                <input
                  type="number"
                  step="0.01"
                  name="medicine[remaining_quantity]"
                  value={@form_data["remaining_quantity"]}
                  class="input input-bordered"
                />
              </div>
            </div>
          </div>

    <!-- Action Buttons -->
          <div class="card-actions justify-center mt-6">
            <button type="submit" class="btn btn-success">
              💾 Save
            </button>
            <button type="button" phx-click="cancel_edit" class="btn btn-neutral">
              ❌ Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # Helper function for formatting expiration dates for inputs
  defp format_expiration_for_input(nil), do: ""
  defp format_expiration_for_input(""), do: ""

  defp format_expiration_for_input(%Date{} = date) do
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    year = date.year |> Integer.to_string()
    "#{year}-#{month}"
  end

  defp format_expiration_for_input(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed_date} -> format_expiration_for_input(parsed_date)
      {:error, _} -> date
    end
  end

  defp format_expiration_for_input(_), do: ""
end
