defmodule Medpack.Medicine do
  use Ecto.Schema
  import Ecto.Changeset

  schema "medicines" do
    # Basic identification
    field :name, :string
    field :brand_name, :string
    field :generic_name, :string
    field :lot_number, :string

    # FHIR Medication.form - dosage form
    field :dosage_form, :string

    # FHIR Medication.ingredient - active substance
    field :active_ingredient, :string
    field :strength_value, :decimal
    field :strength_unit, :string

    # Container/Package information
    field :container_type, :string
    field :total_quantity, :decimal
    field :remaining_quantity, :decimal
    field :quantity_unit, :string

    # Dates and tracking
    field :expiration_date, :date

    # Additional information
    field :manufacturer, :string
    field :photo_paths, {:array, :string}, default: []
    field :default_photo_path, :string

    # Status tracking
    field :status, :string, default: "active"

    timestamps()
  end

  @doc false
  def create_changeset(attrs \\ %{}) do
    %__MODULE__{} |> changeset(attrs)
  end

  @doc """
  Returns a changeset for form display with expiration date formatted for month input.
  """
  def form_changeset(medicine, attrs \\ %{}) do
    # Format expiration date for month input if it exists
    formatted_attrs =
      case medicine.expiration_date do
        %Date{} = date ->
          month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
          year = date.year |> Integer.to_string()
          Map.put(attrs, "expiration_date", "#{year}-#{month}")

        _ ->
          attrs
      end

    changeset(medicine, formatted_attrs)
  end

  def changeset(medicine, attrs) do
    # Handle expiration_date conversion before casting
    converted_attrs = convert_expiration_date_in_attrs(attrs)

    medicine
    |> cast(converted_attrs, [
      :name,
      :brand_name,
      :generic_name,
      :lot_number,
      :dosage_form,
      :active_ingredient,
      :strength_value,
      :strength_unit,
      :container_type,
      :total_quantity,
      :remaining_quantity,
      :quantity_unit,
      :expiration_date,
      :manufacturer,
      :photo_paths,
      :default_photo_path,
      :status
    ])
    |> validate_required([
      :name,
      :dosage_form,
      :container_type,
      :total_quantity
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

  defp convert_expiration_date_in_attrs(attrs) when is_map(attrs) do
    case Map.get(attrs, "expiration_date") do
      value when is_binary(value) ->
        # Handle YYYY-MM format by converting to first day of month
        case Regex.match?(~r/^\d{4}-\d{2}$/, value) do
          true ->
            Map.put(attrs, "expiration_date", "#{value}-01")

          false ->
            attrs
        end

      _ ->
        attrs
    end
  end

  defp convert_expiration_date_in_attrs(attrs), do: attrs

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

    if total && remaining && Decimal.gt?(remaining, total) do
      add_error(changeset, :remaining_quantity, "cannot be greater than total quantity")
    else
      changeset
    end
  end

  def strength_display(%__MODULE__{} = medicine) do
    "#{medicine.strength_value}#{medicine.strength_unit}"
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

  def search_matches(%__MODULE__{} = medicine, search_query)
      when is_binary(search_query) and search_query != "" do
    search_lower = String.downcase(search_query)
    matches = []

    matches =
      if medicine.name && String.contains?(String.downcase(medicine.name), search_lower) do
        [{:name, medicine.name} | matches]
      else
        matches
      end

    matches =
      if medicine.brand_name &&
           String.contains?(String.downcase(medicine.brand_name), search_lower) do
        [{:brand_name, medicine.brand_name} | matches]
      else
        matches
      end

    matches =
      if medicine.generic_name &&
           String.contains?(String.downcase(medicine.generic_name), search_lower) do
        [{:generic_name, medicine.generic_name} | matches]
      else
        matches
      end

    matches =
      if medicine.active_ingredient &&
           String.contains?(String.downcase(medicine.active_ingredient), search_lower) do
        [{:active_ingredient, medicine.active_ingredient} | matches]
      else
        matches
      end

    matches =
      if medicine.manufacturer &&
           String.contains?(String.downcase(medicine.manufacturer), search_lower) do
        [{:manufacturer, medicine.manufacturer} | matches]
      else
        matches
      end

    Enum.reverse(matches)
  end

  def search_matches(%__MODULE__{}, _), do: []
end
