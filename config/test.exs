import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :medpack, Medpack.Repo,
  hostname: "localhost",
  database: "medpack_test",
  port: 5432,
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :medpack, MedpackWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ehMJyDdflDB30qUWw5N0F4/2PTSYkVmpjgxpaPGDn6dfrsvPr13uZqxHtCA829cU",
  server: false

# In test we don't send emails
config :medpack, Medpack.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Configure Oban for testing mode to prevent background processes
# and database connection conflicts with the sandbox
config :medpack, Oban,
  testing: :manual,
  queues: false,
  plugins: false
