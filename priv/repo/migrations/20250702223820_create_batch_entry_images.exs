defmodule Medpack.Repo.Migrations.CreateBatchEntryImages do
  use Ecto.Migration

  def change do
    create table(:batch_entry_images) do
      add :batch_entry_id, references(:batch_entries, type: :uuid, on_delete: :delete_all),
        null: false

      add :s3_key, :string, null: false
      add :original_filename, :string, null: false
      add :file_size, :integer
      add :content_type, :string
      add :upload_order, :integer, default: 0

      timestamps()
    end

    create index(:batch_entry_images, [:batch_entry_id])
    create index(:batch_entry_images, [:batch_entry_id, :upload_order])
  end
end
