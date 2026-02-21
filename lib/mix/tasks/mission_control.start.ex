defmodule Mix.Tasks.MissionControl.Start do
  @moduledoc "Starts the Mission Control Phoenix server on localhost:4000"
  @shortdoc "Starts Mission Control"

  use Mix.Task

  @impl true
  def run(args) do
    config = Application.get_env(:mission_control, MissionControlWeb.Endpoint, [])
    Application.put_env(:mission_control, MissionControlWeb.Endpoint, Keyword.put(config, :server, true))
    Mix.Tasks.Phx.Server.run(args)
  end
end
