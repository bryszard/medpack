defmodule Medpack.Repo.Migrations.CreateMedicines do
  use Ecto.Migration

  def change do
    create table(:medicines) do
      add :name, :string, null: false
      add :type, :string
      add :quantity, :integer
      add :expiration_date, :date
      add :photo_path, :string
      add :notes, :text

      timestamps()
    end

    create index(:medicines, [:name])
    create index(:medicines, [:expiration_date])
  end
end
