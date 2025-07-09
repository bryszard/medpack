defmodule Medpack.Medicines do
  @moduledoc """
  The Medicines context.
  """

  import Ecto.Query, warn: false
  alias Medpack.Repo
  alias Medpack.Medicine

  @doc """
  Returns the list of medicines.

  ## Examples

      iex> list_medicines()
      [%Medicine{}, ...]

  """
  def list_medicines do
    Repo.all(from m in Medicine, order_by: [desc: m.inserted_at])
  end

  @doc """
  Gets a single medicine.

  Returns `nil` if the Medicine does not exist.

  ## Examples

      iex> get_medicine(123)
      %Medicine{}

      iex> get_medicine(456)
      nil

  """
  def get_medicine(id), do: Repo.get(Medicine, id)

  @doc """
  Gets a single medicine.

  Raises `Ecto.NoResultsError` if the Medicine does not exist.

  ## Examples

      iex> get_medicine!(123)
      %Medicine{}

      iex> get_medicine!(456)
      ** (Ecto.NoResultsError)

  """
  def get_medicine!(id), do: Repo.get!(Medicine, id)

  @doc """
  Creates a medicine.

  ## Examples

      iex> create_medicine(%{field: value})
      {:ok, %Medicine{}}

      iex> create_medicine(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_medicine(attrs \\ %{}) do
    %Medicine{}
    |> Medicine.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a medicine.

  ## Examples

      iex> update_medicine(medicine, %{field: new_value})
      {:ok, %Medicine{}}

      iex> update_medicine(medicine, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_medicine(%Medicine{} = medicine, attrs) do
    medicine
    |> Medicine.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a medicine.

  ## Examples

      iex> delete_medicine(medicine)
      {:ok, %Medicine{}}

      iex> delete_medicine(medicine)
      {:error, %Ecto.Changeset{}}

  """
  def delete_medicine(%Medicine{} = medicine) do
    Repo.delete(medicine)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking medicine changes.

  ## Examples

      iex> change_medicine(medicine)
      %Ecto.Changeset{data: %Medicine{}}

  """
  def change_medicine(%Medicine{} = medicine, attrs \\ %{}) do
    Medicine.changeset(medicine, attrs)
  end

  @doc """
  Returns medicines that are expiring soon (within 30 days).
  """
  def list_expiring_medicines do
    thirty_days_from_now = Date.add(Date.utc_today(), 30)

    Repo.all(
      from m in Medicine,
        where:
          m.expiration_date <= ^thirty_days_from_now and m.expiration_date >= ^Date.utc_today(),
        order_by: [asc: m.expiration_date]
    )
  end

  @doc """
  Returns medicines that have already expired.
  """
  def list_expired_medicines do
    today = Date.utc_today()

    Repo.all(
      from m in Medicine,
        where: m.expiration_date < ^today,
        order_by: [asc: m.expiration_date]
    )
  end

  @doc """
  Searches medicines by name, brand name, generic name, active ingredient, and manufacturer.
  """
  def search_medicines(nil), do: []

  def search_medicines(query) when is_binary(query) do
    search_term = "%#{String.downcase(query)}%"

    Repo.all(
      from m in Medicine,
        where:
          like(fragment("lower(?)", m.name), ^search_term) or
            like(fragment("lower(?)", m.brand_name), ^search_term) or
            like(fragment("lower(?)", m.generic_name), ^search_term) or
            like(fragment("lower(?)", m.active_ingredient), ^search_term) or
            like(fragment("lower(?)", m.manufacturer), ^search_term),
        order_by: [desc: m.inserted_at]
    )
  end

  @doc """
  Returns medicines with advanced search and filtering capabilities.
  """
  def search_and_filter_medicines(opts \\ []) do
    Medicine
    |> build_search_query(opts[:search])
    |> build_filter_query(opts[:filters] || %{})
    |> order_by([m], desc: m.inserted_at)
    |> Repo.all()
  end

  defp build_search_query(query, nil), do: query
  defp build_search_query(query, ""), do: query

  defp build_search_query(query, search_term) when is_binary(search_term) do
    search_pattern = "%#{String.downcase(search_term)}%"

    where(
      query,
      [m],
      like(fragment("lower(?)", m.name), ^search_pattern) or
        like(fragment("lower(?)", m.brand_name), ^search_pattern) or
        like(fragment("lower(?)", m.generic_name), ^search_pattern) or
        like(fragment("lower(?)", m.active_ingredient), ^search_pattern) or
        like(fragment("lower(?)", m.manufacturer), ^search_pattern)
    )
  end

  defp build_filter_query(query, filters) when is_map(filters) do
    Enum.reduce(filters, query, fn {key, value}, acc_query ->
      apply_filter(acc_query, key, value)
    end)
  end

  defp apply_filter(query, :dosage_form, value) when is_binary(value) and value != "" do
    where(query, [m], m.dosage_form == ^value)
  end

  defp apply_filter(query, :container_type, value) when is_binary(value) and value != "" do
    where(query, [m], m.container_type == ^value)
  end

  defp apply_filter(query, :status, value) when is_binary(value) and value != "" do
    where(query, [m], m.status == ^value)
  end

  defp apply_filter(query, :expiration_status, "expired") do
    today = Date.utc_today()
    where(query, [m], not is_nil(m.expiration_date) and m.expiration_date < ^today)
  end

  defp apply_filter(query, :expiration_status, "expiring_soon") do
    today = Date.utc_today()
    thirty_days = Date.add(today, 30)

    where(
      query,
      [m],
      not is_nil(m.expiration_date) and
        m.expiration_date >= ^today and
        m.expiration_date <= ^thirty_days
    )
  end

  defp apply_filter(query, :expiration_status, "good") do
    today = Date.utc_today()
    thirty_days = Date.add(today, 30)

    where(
      query,
      [m],
      not is_nil(m.expiration_date) and
        m.expiration_date > ^thirty_days
    )
  end

  defp apply_filter(query, :expiration_status, "unknown") do
    where(query, [m], is_nil(m.expiration_date))
  end

  defp apply_filter(query, _key, _value), do: query
end
