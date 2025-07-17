defmodule Medpack.Repo.Migrations.RemoveStrengthDenominatorFieldsFromMedicines do
  use Ecto.Migration

  def change do
    alter table(:medicines) do
      remove :strength_denominator_value
      remove :strength_denominator_unit
    end
  end
end
