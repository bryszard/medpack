# Script to create a user with password
# Usage: mix run priv/repo/create_user.exs

defmodule CreateUser do
  def create_user(email, password) do
    # Create user with email
    case Medpack.Accounts.register_user(%{email: email}) do
      {:ok, user} ->
        IO.puts("User created: #{user.email}")

        # Confirm the user
        changeset = Medpack.Accounts.User.confirm_changeset(user)
        case Medpack.Repo.update(changeset) do
          {:ok, confirmed_user} ->
            IO.puts("User confirmed: #{confirmed_user.email}")

            # Set password
            case Medpack.Accounts.update_user_password(confirmed_user, %{password: password, password_confirmation: password}) do
              {:ok, user_with_password, _} ->
                IO.puts("Password set for user: #{user_with_password.email}")
                IO.puts("User creation completed successfully!")
                {:ok, user_with_password}
              {:error, changeset} ->
                IO.puts("Error setting password: #{inspect(changeset.errors)}")
                {:error, changeset}
            end
          {:error, changeset} ->
            IO.puts("Error confirming user: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
      {:error, changeset} ->
        IO.puts("Error creating user: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end
end

# Example usage (uncomment and modify as needed):
# CreateUser.create_user("admin@example.com", "password123")
