# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :medpack, :scopes,
  user: [
    default: true,
    module: Medpack.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Medpack.AccountsFixtures,
    test_login_helper: :register_and_log_in_user
  ]

config :medpack,
  ecto_repos: [Medpack.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :medpack, MedpackWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MedpackWeb.ErrorHTML, json: MedpackWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Medpack.PubSub,
  live_view: [signing_salt: "+vfUulMC"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :medpack, Medpack.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  medpack: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  medpack: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Oban for SQLite compatibility
config :medpack, Oban,
  repo: Medpack.Repo,
  plugins: [Oban.Plugins.Pruner],
  notifier: Oban.Notifiers.Isolated,
  # Disable peer coordination for SQLite
  peer: false,
  # Disable table prefixes for SQLite
  prefix: false,
  queues: [
    default: 10,
    ai_analysis: 5,
    file_cleanup: 2
  ]

# Configure OpenAI
config :ex_openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  organization_key: System.get_env("OPENAI_ORGANIZATION_KEY"),
  http_options: [recv_timeout: 30_000]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
