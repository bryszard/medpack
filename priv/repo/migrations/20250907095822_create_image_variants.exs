defmodule Medpack.Repo.Migrations.CreateImageVariants do
  use Ecto.Migration

  def change do
    create table(:image_variants) do
      add :medicine_id, references(:medicines, on_delete: :delete_all), null: false
      add :original_path, :string, null: false
      add :variant_size, :string, null: false
      add :variant_path, :string, null: false
      add :processing_status, :string, default: "pending", null: false
      add :processing_error, :text
      add :processed_at, :utc_datetime

      timestamps()
    end

    create index(:image_variants, [:medicine_id])
    create index(:image_variants, [:original_path])
    create index(:image_variants, [:processing_status])
    create unique_index(:image_variants, [:medicine_id, :original_path, :variant_size])
  end
end
