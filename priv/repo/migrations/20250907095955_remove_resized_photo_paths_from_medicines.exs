defmodule Medpack.Repo.Migrations.RemoveResizedPhotoPathsFromMedicines do
  use Ecto.Migration

  def change do
    alter table(:medicines) do
      remove :resized_photo_paths, :map
    end
  end
end
