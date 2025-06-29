defmodule MedicineInventory.Repo.Migrations.RemoveNdcCodeFromMedicines do
  use Ecto.Migration

  def change do
    alter table(:medicines) do
      remove :ndc_code, :string
    end
  end
end
