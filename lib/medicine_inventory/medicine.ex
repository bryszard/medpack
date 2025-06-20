defmodule MedicineInventory.Medicine do
  use Ecto.Schema
  import Ecto.Changeset

  schema "medicines" do
    field :name, :string
    field :type, :string
    field :quantity, :integer
    field :expiration_date, :date
    field :photo_path, :string
    field :notes, :string

    timestamps()
  end

  @doc false
  def changeset(medicine, attrs) do
    medicine
    |> cast(attrs, [:name, :type, :quantity, :expiration_date, :photo_path, :notes])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
  end

  def create_changeset(attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  def days_until_expiration(%__MODULE__{expiration_date: nil}), do: nil

  def days_until_expiration(%__MODULE__{expiration_date: expiration_date}) do
    Date.diff(expiration_date, Date.utc_today())
  end

  def expiration_status(medicine) do
    case days_until_expiration(medicine) do
      nil -> :unknown
      days when days < 0 -> :expired
      days when days <= 30 -> :expiring_soon
      _ -> :good
    end
  end
end
