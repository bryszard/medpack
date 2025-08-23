defmodule Medpack.Repo.Migrations.AddResizedPhotoPathsToMedicines do
  use Ecto.Migration

  def change do
    alter table(:medicines) do
      add :resized_photo_paths, :map, default: %{}
    end
  end
end
