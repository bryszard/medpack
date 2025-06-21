defmodule MedicineInventory.Repo.Migrations.RedesignMedicinesWithFhirModel do
  use Ecto.Migration

  def change do
    # Drop the old simple medicines table
    drop table(:medicines)

    # Create new FHIR-inspired medicines table
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

      # FHIR Medication.ingredient - active substance
      add :active_ingredient, :string, null: false
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
      # current amount
      add :remaining_quantity, :decimal, precision: 10, scale: 3, null: false
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

    # Add indexes for common queries
    create index(:medicines, [:name])
    create index(:medicines, [:dosage_form])
    create index(:medicines, [:expiration_date])
    create index(:medicines, [:status])
    create index(:medicines, [:active_ingredient])
  end
end
