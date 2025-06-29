defmodule MedicineInventory.BatchProcessing.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "batch_entries" do
    field :batch_id, :string
    field :entry_number, :integer
    field :status, Ecto.Enum, values: [:pending, :processing, :complete, :failed]

    # File information
    field :photo_path, :string
    field :original_filename, :string
    field :file_size, :integer
    field :content_type, :string

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

    timestamps()
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :batch_id,
      :entry_number,
      :status,
      :photo_path,
      :original_filename,
      :file_size,
      :content_type,
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
    |> validate_number(:file_size, greater_than: 0)
    |> validate_inclusion(:content_type, ["image/jpeg", "image/png", "image/jpg"])
    |> unique_constraint([:batch_id, :entry_number])
  end

  @doc """
  Returns true if the entry has an uploaded photo.
  """
  def has_photo?(%__MODULE__{} = entry) do
    not is_nil(entry.photo_path) and File.exists?(entry.photo_path)
  end

  @doc """
  Returns true if the entry is ready for analysis.
  """
  def ready_for_analysis?(%__MODULE__{} = entry) do
    has_photo?(entry) and entry.ai_analysis_status == :pending
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
    case {has_photo?(entry), entry.ai_analysis_status, entry.approval_status} do
      {false, _, _} -> "Ready for upload"
      {true, :pending, _} -> "Photo uploaded"
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
    case {has_photo?(entry), entry.ai_analysis_status, entry.approval_status} do
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
end
