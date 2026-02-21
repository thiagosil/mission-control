defmodule MissionControl.Repo do
  use Ecto.Repo,
    otp_app: :mission_control,
    adapter: Ecto.Adapters.SQLite3
end
