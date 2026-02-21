defmodule MissionControl.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(running stopped crashed)

  schema "agents" do
    field :name, :string
    field :role, :string
    field :status, :string, default: "stopped"
    field :config, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:name, :role, :status, :config])
    |> validate_required([:name, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
