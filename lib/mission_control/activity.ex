defmodule MissionControl.Activity do
  import Ecto.Query
  alias MissionControl.Repo
  alias MissionControl.Activity.Event

  def append(attrs) do
    case %Event{} |> Event.changeset(attrs) |> Repo.insert() do
      {:ok, event} ->
        event = Repo.preload(event, [:agent, :task])
        Phoenix.PubSub.broadcast(MissionControl.PubSub, "activity", {:new_event, event})
        {:ok, event}

      error ->
        error
    end
  end

  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Event
    |> apply_filter(:type, Keyword.get(opts, :type))
    |> apply_filter(:agent_id, Keyword.get(opts, :agent_id))
    |> apply_filter(:task_id, Keyword.get(opts, :task_id))
    |> apply_since(Keyword.get(opts, :since))
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload([:agent, :task])
  end

  def subscribe do
    Phoenix.PubSub.subscribe(MissionControl.PubSub, "activity")
  end

  defp apply_filter(query, _field, nil), do: query
  defp apply_filter(query, :type, type), do: where(query, [e], e.type == ^type)
  defp apply_filter(query, :agent_id, id), do: where(query, [e], e.agent_id == ^id)
  defp apply_filter(query, :task_id, id), do: where(query, [e], e.task_id == ^id)

  defp apply_since(query, nil), do: query
  defp apply_since(query, since), do: where(query, [e], e.inserted_at >= ^since)
end
