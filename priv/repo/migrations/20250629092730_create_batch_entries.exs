defmodule Medpack.Repo.Migrations.CreateBatchEntries do
  use Ecto.Migration

  def change do
    create table(:batch_entries) do
      add :batch_id, :string, null: false
      add :entry_number, :integer, null: false
      add :status, :string, default: "pending"

      # File information
      add :photo_path, :string
      add :original_filename, :string
      add :file_size, :integer
      add :content_type, :string

      # AI analysis
      add :ai_analysis_status, :string, default: "pending"
      add :ai_results, :map
      add :analyzed_at, :utc_datetime
      add :error_message, :text

      # Human review
      add :approval_status, :string, default: "pending"
      add :reviewed_by, :string
      add :reviewed_at, :utc_datetime
      add :review_notes, :text

      timestamps()
    end

    # Indexes for efficient queries
    create index(:batch_entries, [:batch_id])
    create index(:batch_entries, [:ai_analysis_status])
    create index(:batch_entries, [:approval_status])
    create index(:batch_entries, [:status])
    create unique_index(:batch_entries, [:batch_id, :entry_number])
  end
end
