defmodule Medpack.Repo.Migrations.AddDefaultPhotoPathToMedicines do
  use Ecto.Migration

  def change do
    alter table(:medicines) do
      add :default_photo_path, :string
    end
  end
end
