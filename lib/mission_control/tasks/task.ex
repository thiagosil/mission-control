defmodule MissionControl.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @columns ~w(inbox assigned in_progress review done)
  @priorities ~w(normal urgent)

  @valid_transitions %{
    "inbox" => ["assigned"],
    "assigned" => ["inbox", "in_progress"],
    "in_progress" => ["assigned", "review"],
    "review" => ["in_progress", "done"],
    "done" => ["review"]
  }

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :column, :string, default: "inbox"
    field :priority, :string, default: "normal"
    field :tags, {:array, :string}, default: []
    field :branch_name, :string
    field :dependencies, {:array, :integer}, default: []

    belongs_to :agent, MissionControl.Agents.Agent

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :description,
      :column,
      :agent_id,
      :priority,
      :tags,
      :branch_name,
      :dependencies
    ])
    |> validate_required([:title, :column])
    |> validate_inclusion(:column, @columns)
    |> validate_inclusion(:priority, @priorities)
  end

  def columns, do: @columns
  def valid_transitions, do: @valid_transitions

  def valid_transition?(from, to) do
    to in Map.get(@valid_transitions, from, [])
  end
end
