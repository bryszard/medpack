defmodule MedpackWeb.UserLive.Settings do
  use MedpackWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl space-y-4">
        <.header class="text-center">
          <p>Account Settings</p>
        </.header>

        <div class="space-y-4">
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title">Account Information</h2>
              <div class="space-y-2">
                <div>
                  <span class="font-semibold">Email:</span>
                  <span><%= @current_scope.user.email %></span>
                </div>
                <div>
                  <span class="font-semibold">Account Status:</span>
                  <span class="badge badge-success">Active</span>
                </div>
              </div>
            </div>
          </div>

          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title">Actions</h2>
              <div class="space-y-2">
                <.link
                  href={~p"/users/log-out"}
                  method="delete"
                  class="btn btn-error"
                >
                  Sign out
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
