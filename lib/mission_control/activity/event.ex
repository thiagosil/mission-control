defmodule MissionControl.Activity.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_types ~w(agent_spawned agent_stopped agent_restarted agent_exited task_created task_updated task_deleted task_assigned)

  schema "events" do
    field :type, :string
    field :message, :string
    field :metadata, :map, default: %{}

    belongs_to :agent, MissionControl.Agents.Agent
    belongs_to :task, MissionControl.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:type, :message, :metadata, :agent_id, :task_id])
    |> validate_required([:type, :message])
    |> validate_inclusion(:type, @valid_types)
  end

  def valid_types, do: @valid_types
end
