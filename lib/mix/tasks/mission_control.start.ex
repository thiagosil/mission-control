defmodule Mix.Tasks.MissionControl.Start do
  @moduledoc "Starts the Mission Control Phoenix server on localhost:4000"
  @shortdoc "Starts Mission Control"

  use Mix.Task

  @impl true
  def run(args) do
    Application.put_env(:mission_control, MissionControlWeb.Endpoint, server: true, merge: true)
    Mix.Tasks.Phx.Server.run(args)
  end
end
