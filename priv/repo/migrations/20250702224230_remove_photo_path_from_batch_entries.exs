defmodule Medpack.Repo.Migrations.RemovePhotoPathFromBatchEntries do
  use Ecto.Migration

  def change do
    alter table(:batch_entries) do
      remove :photo_path, :text
    end
  end
end
