defmodule Medpack.Repo do
  use Ecto.Repo,
    otp_app: :medpack,
    adapter: Ecto.Adapters.Postgres
end
