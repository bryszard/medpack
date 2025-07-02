defmodule Medpack.Jobs.CleanupFilesJob do
  @moduledoc """
  Background job for cleaning up old temporary files.
  """

  use Oban.Worker, queue: :file_cleanup, max_attempts: 1

  alias Medpack.FileManager

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    max_age_hours = Map.get(args, "max_age_hours", 24)

    Logger.info("Starting file cleanup for files older than #{max_age_hours} hours")

    case FileManager.cleanup_temp_files(max_age_hours) do
      :ok ->
        Logger.info("File cleanup completed successfully")
        :ok

      {:error, reason} ->
        Logger.error("File cleanup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Schedules a file cleanup job to run periodically.
  """
  def schedule_cleanup(max_age_hours \\ 24) do
    %{max_age_hours: max_age_hours}
    # Run every hour
    |> __MODULE__.new(queue: :file_cleanup, schedule_in: 3600)
    |> Oban.insert()
  end
end
