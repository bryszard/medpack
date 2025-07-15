defmodule Medpack.Repo.Migrations.CreateBatchEntries do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

    create table(:batch_entries, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
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

      timestamps()
    end

    # Indexes for efficient queries
    create index(:batch_entries, [:ai_analysis_status])
    create index(:batch_entries, [:status])
  end
end
