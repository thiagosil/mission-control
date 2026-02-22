defmodule MissionControl.Tasks do
  import Ecto.Query
  alias MissionControl.Repo
  alias MissionControl.Tasks.Task

  # --- CRUD ---

  def list_tasks do
    Task |> order_by(asc: :id) |> Repo.all()
  end

  def list_tasks_by_column(column) do
    Task |> where(column: ^column) |> order_by(asc: :id) |> Repo.all()
  end

  def get_task!(id), do: Repo.get!(Task, id)

  def create_task(attrs) do
    case %Task{} |> Task.changeset(attrs) |> Repo.insert() do
      {:ok, task} ->
        broadcast_task_change({:task_created, task})
        {:ok, task}

      error ->
        error
    end
  end

  def update_task(%Task{} = task, attrs) do
    case task |> Task.changeset(attrs) |> Repo.update() do
      {:ok, task} ->
        broadcast_task_change({:task_updated, task})
        {:ok, task}

      error ->
        error
    end
  end

  def delete_task(%Task{} = task) do
    case Repo.delete(task) do
      {:ok, task} ->
        broadcast_task_change({:task_deleted, task})
        {:ok, task}

      error ->
        error
    end
  end

  # --- State transitions ---

  def move_task(%Task{} = task, new_column) do
    if Task.valid_transition?(task.column, new_column) do
      update_task(task, %{column: new_column})
    else
      {:error, :invalid_transition}
    end
  end

  # --- Assignment ---

  def assign_and_start_task(%Task{} = task) do
    alias MissionControl.Git

    with {:ok, branch_name} <- Git.create_branch(task),
         :ok <- Git.checkout_branch(branch_name),
         {:ok, agent} <-
           MissionControl.Agents.spawn_agent_for_task(task, branch_name: branch_name),
         {:ok, task} <-
           update_task(task, %{agent_id: agent.id, column: "assigned", branch_name: branch_name}),
         {:ok, task} <- move_task(task, "in_progress") do
      {:ok, task, agent}
    end
  end

  def assign_task_to_existing_agent(%Task{} = task, agent_id) do
    alias MissionControl.Git

    with {:ok, branch_name} <- Git.create_branch(task),
         :ok <- Git.checkout_branch(branch_name),
         {:ok, task} <-
           update_task(task, %{agent_id: agent_id, column: "assigned", branch_name: branch_name}),
         {:ok, task} <- move_task(task, "in_progress") do
      {:ok, task}
    end
  end

  def get_task_for_agent(agent_id) do
    Task
    |> where([t], t.agent_id == ^agent_id and t.column in ["assigned", "in_progress"])
    |> Repo.one()
  end

  def get_task_for_agent_by_id(task_id) do
    Repo.get(Task, task_id)
  end

  # --- PubSub ---

  def subscribe do
    Phoenix.PubSub.subscribe(MissionControl.PubSub, "tasks")
  end

  defp broadcast_task_change(message) do
    Phoenix.PubSub.broadcast(MissionControl.PubSub, "tasks", message)
  end
end
