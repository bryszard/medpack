defmodule MedpackWeb.Router do
  use MedpackWeb, :router

  import MedpackWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MedpackWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MedpackWeb do
    pipe_through [:browser]

    get "/", PageController, :home
    get "/images/:path", ImageController, :show
  end

  scope "/", MedpackWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated_app,
      on_mount: [{MedpackWeb.UserAuth, :require_authenticated}] do
      live "/inventory", MedicineLive
      live "/inventory/:id", MedicineShowLive
      live "/add", BatchMedicineLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", MedpackWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:medpack, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MedpackWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", MedpackWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{MedpackWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  scope "/", MedpackWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated_settings,
      on_mount: [{MedpackWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
    end
  end
end
