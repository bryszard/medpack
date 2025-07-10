defmodule Medpack.BatchProcessing.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  alias Medpack.BatchProcessing.EntryImage

  schema "batch_entries" do
    field :batch_id, :string
    field :entry_number, :integer
    field :status, Ecto.Enum, values: [:pending, :processing, :complete, :failed]

    # File information is now handled by EntryImage schema

    # AI analysis
    field :ai_analysis_status, Ecto.Enum, values: [:pending, :processing, :complete, :failed]
    field :ai_results, :map
    field :analyzed_at, :utc_datetime
    field :error_message, :string

    # Human review
    field :approval_status, Ecto.Enum, values: [:pending, :approved, :rejected]
    field :reviewed_by, :string
    field :reviewed_at, :utc_datetime
    field :review_notes, :string

    # Relationships
    has_many :images, EntryImage, foreign_key: :batch_entry_id

    timestamps()
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :batch_id,
      :entry_number,
      :status,
      :ai_analysis_status,
      :ai_results,
      :analyzed_at,
      :error_message,
      :approval_status,
      :reviewed_by,
      :reviewed_at,
      :review_notes
    ])
    |> validate_required([:batch_id, :entry_number])
    |> validate_number(:entry_number, greater_than: 0)
    |> unique_constraint([:batch_id, :entry_number])
    |> put_default_values()
  end

  defp put_default_values(changeset) do
    changeset
    |> put_change(:status, get_change(changeset, :status) || :pending)
    |> put_change(:ai_analysis_status, get_change(changeset, :ai_analysis_status) || :pending)
    |> put_change(:approval_status, get_change(changeset, :approval_status) || :pending)
  end

  @doc """
  Returns true if the entry has uploaded photos.
  """
  def has_photos?(%__MODULE__{images: images}) when is_list(images) do
    length(images) > 0
  end

  def has_photos?(%__MODULE__{} = entry) do
    # For entries without preloaded images, we need to query
    Medpack.BatchProcessing.list_entry_images(entry.id) |> length() > 0
  end

  @doc """
  Returns true if the entry is ready for analysis.
  """
  def ready_for_analysis?(%__MODULE__{} = entry) do
    has_photos?(entry) and entry.ai_analysis_status == :pending
  end

  @doc """
  Returns true if the entry analysis is complete.
  """
  def analysis_complete?(%__MODULE__{} = entry) do
    entry.ai_analysis_status == :complete and not is_nil(entry.ai_results)
  end

  @doc """
  Returns true if the entry is approved and ready to save.
  """
  def ready_to_save?(%__MODULE__{} = entry) do
    analysis_complete?(entry) and entry.approval_status == :approved
  end

  @doc """
  Returns a human-readable status for the entry.
  """
  def status_text(%__MODULE__{} = entry) do
    case {has_photos?(entry), entry.ai_analysis_status, entry.approval_status} do
      {false, _, _} -> "Ready for upload"
      {true, :pending, _} -> "Photos uploaded"
      {true, :processing, _} -> "Analyzing..."
      {true, :complete, :pending} -> "Pending review"
      {true, :complete, :approved} -> "Approved"
      {true, :complete, :rejected} -> "Rejected"
      {true, :failed, _} -> "Analysis failed"
    end
  end

  # Handle LiveView in-memory maps (backward compatibility)
  def status_text(%{
        photos_uploaded: photos_uploaded,
        ai_analysis_status: ai_status,
        approval_status: approval_status
      }) do
    has_photos = photos_uploaded > 0

    case {has_photos, ai_status, approval_status} do
      {false, _, _} -> "Ready for upload"
      {true, :pending, _} -> "Photos uploaded"
      {true, :processing, _} -> "Analyzing..."
      {true, :complete, :pending} -> "Pending review"
      {true, :complete, :approved} -> "Approved"
      {true, :complete, :rejected} -> "Rejected"
      {true, :failed, _} -> "Analysis failed"
    end
  end

  @doc """
  Returns an emoji icon for the entry status.
  """
  def status_icon(%__MODULE__{} = entry) do
    case {has_photos?(entry), entry.ai_analysis_status, entry.approval_status} do
      {false, _, _} -> "⬆️"
      {true, :pending, _} -> "📸"
      {true, :processing, _} -> "🔍"
      {true, :complete, :pending} -> "⏳"
      {true, :complete, :approved} -> "✅"
      {true, :complete, :rejected} -> "❌"
      {true, :failed, _} -> "⚠️"
    end
  end

  # Handle LiveView in-memory maps (backward compatibility)
  def status_icon(%{
        photos_uploaded: photos_uploaded,
        ai_analysis_status: ai_status,
        approval_status: approval_status
      }) do
    has_photos = photos_uploaded > 0

    case {has_photos, ai_status, approval_status} do
      {false, _, _} -> "⬆️"
      {true, :pending, _} -> "📸"
      {true, :processing, _} -> "🔍"
      {true, :complete, :pending} -> "⏳"
      {true, :complete, :approved} -> "✅"
      {true, :complete, :rejected} -> "❌"
      {true, :failed, _} -> "⚠️"
    end
  end

  @doc """
  Returns a summary of the AI analysis results.
  """
  def ai_results_summary(%__MODULE__{ai_results: ai_results})
      when is_map(ai_results) and map_size(ai_results) > 0 do
    name = Map.get(ai_results, "name", "Unknown")
    form = Map.get(ai_results, "dosage_form", "")

    strength =
      "#{Map.get(ai_results, "strength_value", "")}#{Map.get(ai_results, "strength_unit", "")}"

    "#{name} • #{String.capitalize(form)} • #{strength}"
  end

  def ai_results_summary(_), do: "No analysis data"

  @doc """
  Returns missing required fields for this entry.
  """
  def missing_required_fields(%__MODULE__{ai_results: ai_results}) when is_map(ai_results) do
    required_fields = [
      {"name", "Medicine Name"},
      {"dosage_form", "Dosage Form"},
      {"strength_value", "Strength Value"},
      {"strength_unit", "Strength Unit"},
      {"container_type", "Container Type"},
      {"total_quantity", "Total Quantity"},
      {"quantity_unit", "Quantity Unit"}
    ]

    required_fields
    |> Enum.filter(fn {field_key, _field_name} ->
      value = Map.get(ai_results, field_key)
      is_nil(value) or value == ""
    end)
    |> Enum.map(fn {_field_key, field_name} -> field_name end)
  end

  # Handle LiveView in-memory maps (backward compatibility)
  def missing_required_fields(%{ai_results: ai_results}) when is_map(ai_results) do
    required_fields = [
      {"name", "Medicine Name"},
      {"dosage_form", "Dosage Form"},
      {"strength_value", "Strength Value"},
      {"strength_unit", "Strength Unit"},
      {"container_type", "Container Type"},
      {"total_quantity", "Total Quantity"},
      {"quantity_unit", "Quantity Unit"}
    ]

    required_fields
    |> Enum.filter(fn {field_key, _field_name} ->
      value = Map.get(ai_results, field_key)
      is_nil(value) or value == ""
    end)
    |> Enum.map(fn {_field_key, field_name} -> field_name end)
  end

  def missing_required_fields(_), do: []

  @doc """
  Returns the status of a specific field extraction.
  """
  def field_status(%__MODULE__{ai_results: ai_results}, field_key) when is_map(ai_results) do
    value = Map.get(ai_results, field_key)

    case value do
      nil -> :missing
      "" -> :missing
      _ -> {:present, format_field_value(field_key, value)}
    end
  end

  # Handle LiveView in-memory maps (backward compatibility)
  def field_status(%{ai_results: ai_results}, field_key) when is_map(ai_results) do
    value = Map.get(ai_results, field_key)

    case value do
      nil -> :missing
      "" -> :missing
      _ -> {:present, format_field_value(field_key, value)}
    end
  end

  def field_status(_, _), do: :missing

  @doc """
  Formats a field value for display.
  """
  def format_field_value("dosage_form", value), do: String.capitalize(value)

  def format_field_value("container_type", value),
    do: String.capitalize(String.replace(value, "_", " "))

  def format_field_value("strength_value", value) when is_number(value), do: "#{value}"
  def format_field_value("total_quantity", value) when is_number(value), do: "#{value}"
  def format_field_value("remaining_quantity", value) when is_number(value), do: "#{value}"
  def format_field_value(_field, value), do: "#{value}"

  @doc """
  Returns the number of photos uploaded for this entry.
  """
  def photos_count(%__MODULE__{images: images}) when is_list(images), do: length(images)

  def photos_count(%__MODULE__{} = entry) do
    # For entries without preloaded images, we need to query
    Medpack.BatchProcessing.list_entry_images(entry.id) |> length()
  end

  @doc """
  Returns display data for this entry's photos.
  """
  def photo_display_data(%__MODULE__{images: images}) when is_list(images) do
    images
    |> Enum.sort_by(& &1.upload_order)
    |> Enum.map(fn image ->
      %{
        web_url: Medpack.BatchProcessing.EntryImage.get_s3_url(image),
        filename: image.original_filename,
        size: image.file_size,
        human_size: Medpack.BatchProcessing.EntryImage.human_file_size(image)
      }
    end)
  end

  def photo_display_data(%__MODULE__{} = _entry) do
    # For entries without preloaded images, return empty for now
    # In a real scenario, you might want to lazy-load this
    []
  end

  @doc """
  Returns whether this entry is ready for the next action.
  """
  def next_action(%__MODULE__{} = entry) do
    cond do
      not has_photos?(entry) -> :upload_photos
      entry.ai_analysis_status == :pending -> :analyze
      entry.ai_analysis_status == :processing -> :wait_for_analysis
      entry.ai_analysis_status == :failed -> :retry_analysis
      entry.ai_analysis_status == :complete and entry.approval_status == :pending -> :review
      entry.approval_status == :approved -> :save
      entry.approval_status == :rejected -> :rejected
      true -> :unknown
    end
  end

  @doc """
  Returns the CSS classes for styling this entry's status.
  """
  def status_css_classes(%__MODULE__{} = entry) do
    case {has_photos?(entry), entry.ai_analysis_status, entry.approval_status} do
      {false, _, _} -> "border-gray-300 bg-gray-50"
      {true, :pending, _} -> "border-blue-300 bg-blue-50"
      {true, :processing, _} -> "border-yellow-300 bg-yellow-50"
      {true, :complete, :pending} -> "border-orange-300 bg-orange-50"
      {true, :complete, :approved} -> "border-green-300 bg-green-50"
      {true, :complete, :rejected} -> "border-red-300 bg-red-50"
      {true, :failed, _} -> "border-red-300 bg-red-50"
    end
  end
end
