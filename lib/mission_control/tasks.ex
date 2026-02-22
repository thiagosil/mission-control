defmodule MissionControl.Tasks do
  import Ecto.Query
  alias MissionControl.Activity
  alias MissionControl.Repo
  alias MissionControl.Tasks.Task

  @git Application.compile_env(:mission_control, :git_module, MissionControl.Git)

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

        Activity.append(%{
          type: "task_created",
          task_id: task.id,
          message: "Task \"#{task.title}\" created"
        })

        {:ok, task}

      error ->
        error
    end
  end

  def update_task(%Task{} = task, attrs) do
    case task |> Task.changeset(attrs) |> Repo.update() do
      {:ok, task} ->
        broadcast_task_change({:task_updated, task})

        Activity.append(%{
          type: "task_updated",
          task_id: task.id,
          message: "Task \"#{task.title}\" updated"
        })

        {:ok, task}

      error ->
        error
    end
  end

  def delete_task(%Task{} = task) do
    # Capture task info before deletion for the activity event
    task_title = task.title

    case Repo.delete(task) do
      {:ok, task} ->
        broadcast_task_change({:task_deleted, task})

        Activity.append(%{
          type: "task_deleted",
          message: "Task \"#{task_title}\" deleted"
        })

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
    with {:ok, branch_name} <- @git.create_branch(task),
         :ok <- @git.checkout_branch(branch_name),
         {:ok, agent} <-
           MissionControl.Agents.spawn_agent_for_task(task, branch_name: branch_name),
         {:ok, task} <-
           update_task(task, %{agent_id: agent.id, column: "assigned", branch_name: branch_name}),
         {:ok, task} <- move_task(task, "in_progress") do
      Activity.append(%{
        type: "task_assigned",
        task_id: task.id,
        agent_id: agent.id,
        message: "Task \"#{task.title}\" assigned to #{agent.name}",
        metadata: %{"branch" => branch_name}
      })

      {:ok, task, agent}
    end
  end

  def assign_task_to_existing_agent(%Task{} = task, agent_id) do
    with {:ok, branch_name} <- @git.create_branch(task),
         :ok <- @git.checkout_branch(branch_name),
         {:ok, task} <-
           update_task(task, %{agent_id: agent_id, column: "assigned", branch_name: branch_name}),
         {:ok, task} <- move_task(task, "in_progress") do
      agent = MissionControl.Agents.get_agent!(agent_id)

      Activity.append(%{
        type: "task_assigned",
        task_id: task.id,
        agent_id: agent_id,
        message: "Task \"#{task.title}\" assigned to #{agent.name}",
        metadata: %{"branch" => branch_name}
      })

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
