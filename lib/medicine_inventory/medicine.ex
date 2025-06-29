defmodule MedicineInventory.Medicine do
  use Ecto.Schema
  import Ecto.Changeset

  schema "medicines" do
    # Basic identification
    field :name, :string
    field :brand_name, :string
    field :generic_name, :string
    field :ndc_code, :string
    field :lot_number, :string

    # FHIR Medication.form - dosage form
    field :dosage_form, :string

    # FHIR Medication.ingredient - active substance
    field :active_ingredient, :string
    field :strength_value, :decimal
    field :strength_unit, :string
    field :strength_denominator_value, :decimal
    field :strength_denominator_unit, :string

    # Container/Package information
    field :container_type, :string
    field :total_quantity, :decimal
    field :remaining_quantity, :decimal
    field :quantity_unit, :string

    # Dates and tracking
    field :expiration_date, :date
    field :date_opened, :date
    field :purchase_date, :date

    # Additional information
    field :manufacturer, :string
    field :indication, :string
    field :notes, :string
    field :photo_paths, {:array, :string}, default: []

    # Status tracking
    field :status, :string, default: "active"

    timestamps()
  end

  @doc false
  def create_changeset(attrs \\ %{}) do
    %__MODULE__{} |> changeset(attrs)
  end

  def changeset(medicine, attrs) do
    medicine
    |> cast(attrs, [
      :name,
      :brand_name,
      :generic_name,
      :ndc_code,
      :lot_number,
      :dosage_form,
      :active_ingredient,
      :strength_value,
      :strength_unit,
      :strength_denominator_value,
      :strength_denominator_unit,
      :container_type,
      :total_quantity,
      :remaining_quantity,
      :quantity_unit,
      :expiration_date,
      :date_opened,
      :purchase_date,
      :manufacturer,
      :indication,
      :notes,
      :photo_paths,
      :status
    ])
    |> validate_required([
      :name,
      :dosage_form,
      :strength_value,
      :strength_unit,
      :container_type,
      :total_quantity,
      :quantity_unit
    ])
    |> validate_inclusion(:dosage_form, [
      "tablet",
      "capsule",
      "syrup",
      "suspension",
      "solution",
      "cream",
      "ointment",
      "gel",
      "lotion",
      "drops",
      "injection",
      "inhaler",
      "spray",
      "patch",
      "suppository"
    ])
    |> validate_inclusion(:container_type, [
      "bottle",
      "box",
      "tube",
      "vial",
      "inhaler",
      "blister_pack",
      "sachet",
      "ampoule"
    ])
    |> validate_inclusion(:status, ["active", "expired", "empty", "recalled"])
    |> set_default_remaining_quantity()
    |> validate_number(:strength_value, greater_than: 0)
    |> validate_number(:total_quantity, greater_than: 0)
    |> validate_number(:remaining_quantity, greater_than_or_equal_to: 0)
    |> validate_remaining_quantity_not_greater_than_total()
  end

  defp set_default_remaining_quantity(changeset) do
    total = get_field(changeset, :total_quantity)
    remaining = get_field(changeset, :remaining_quantity)

    # If remaining_quantity is not set but total_quantity is, default remaining to total
    if total && is_nil(remaining) do
      put_change(changeset, :remaining_quantity, total)
    else
      changeset
    end
  end

  defp validate_remaining_quantity_not_greater_than_total(changeset) do
    total = get_field(changeset, :total_quantity)
    remaining = get_field(changeset, :remaining_quantity)

    if total && remaining && remaining > total do
      add_error(changeset, :remaining_quantity, "cannot be greater than total quantity")
    else
      changeset
    end
  end

  def strength_display(%__MODULE__{} = medicine) do
    base = "#{medicine.strength_value}#{medicine.strength_unit}"

    if medicine.strength_denominator_value do
      "#{base}/#{medicine.strength_denominator_value}#{medicine.strength_denominator_unit}"
    else
      base
    end
  end

  def quantity_display(%__MODULE__{} = medicine) do
    "#{medicine.remaining_quantity}/#{medicine.total_quantity} #{medicine.quantity_unit}"
  end

  def usage_percentage(%__MODULE__{} = medicine) do
    if Decimal.to_float(medicine.total_quantity) > 0 do
      (Decimal.to_float(medicine.remaining_quantity) / Decimal.to_float(medicine.total_quantity) *
         100)
      |> Float.round(1)
    else
      0.0
    end
  end
end
