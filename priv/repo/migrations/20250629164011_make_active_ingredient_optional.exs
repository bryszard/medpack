defmodule MedicineInventory.Repo.Migrations.MakeActiveIngredientOptional do
  use Ecto.Migration

  def change do
    # SQLite doesn't support ALTER COLUMN, so we need to recreate the table

    # First, rename the current table
    rename table(:medicines), to: table(:medicines_old)

    # Create new table with optional active_ingredient and remaining_quantity
    create table(:medicines) do
      # Basic identification
      add :name, :string, null: false
      add :brand_name, :string
      add :generic_name, :string
      # National Drug Code or similar identifier
      add :ndc_code, :string
      add :lot_number, :string

      # FHIR Medication.form - dosage form
      # tablet, capsule, syrup, cream, etc.
      add :dosage_form, :string, null: false

      # FHIR Medication.ingredient - active substance (NOW OPTIONAL)
      add :active_ingredient, :string, null: true
      # e.g., 10.5
      add :strength_value, :decimal, precision: 10, scale: 3
      # mg, ml, g, IU, etc.
      add :strength_unit, :string, null: false
      # for mg/ml ratios
      add :strength_denominator_value, :decimal, precision: 10, scale: 3
      # ml, g, tablet, etc.
      add :strength_denominator_unit, :string

      # Container/Package information
      # bottle, box, tube, vial, inhaler
      add :container_type, :string, null: false
      # total in container
      add :total_quantity, :decimal, precision: 10, scale: 3, null: false
      # current amount (NOW OPTIONAL)
      add :remaining_quantity, :decimal, precision: 10, scale: 3, null: true
      # ml, tablets, g, doses
      add :quantity_unit, :string, null: false

      # Dates and tracking
      add :expiration_date, :date
      add :date_opened, :date
      add :purchase_date, :date

      # Additional information
      add :manufacturer, :string
      # what it's used for
      add :indication, :text
      add :notes, :text
      add :photo_paths, {:array, :string}, default: []

      # Status tracking
      # active, expired, empty, recalled
      add :status, :string, default: "active"

      timestamps()
    end

    # Copy data from old table to new table
    execute """
    INSERT INTO medicines (
      name, brand_name, generic_name, ndc_code, lot_number, dosage_form,
      active_ingredient, strength_value, strength_unit, strength_denominator_value,
      strength_denominator_unit, container_type, total_quantity, remaining_quantity,
      quantity_unit, expiration_date, date_opened, purchase_date, manufacturer,
      indication, notes, photo_paths, status, inserted_at, updated_at
    )
    SELECT
      name, brand_name, generic_name, ndc_code, lot_number, dosage_form,
      active_ingredient, strength_value, strength_unit, strength_denominator_value,
      strength_denominator_unit, container_type, total_quantity, remaining_quantity,
      quantity_unit, expiration_date, date_opened, purchase_date, manufacturer,
      indication, notes, photo_paths, status, inserted_at, updated_at
    FROM medicines_old
    """

    # Drop the old table
    drop table(:medicines_old)

    # Recreate indexes
    create index(:medicines, [:name])
    create index(:medicines, [:dosage_form])
    create index(:medicines, [:expiration_date])
    create index(:medicines, [:status])
    create index(:medicines, [:active_ingredient])
  end
end
