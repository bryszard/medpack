defmodule MedicineInventory.Repo do
  use Ecto.Repo,
    otp_app: :medicine_inventory,
    adapter: Ecto.Adapters.SQLite3
end
