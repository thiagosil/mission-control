defmodule MissionControl.Git do
  @moduledoc """
  Git operations for branch-per-task workflow.
  Creates and manages `mc/<task-id>-<slug>` branches.
  """

  @doc """
  Generates a branch name from a task: `mc/<id>-<slugified-title>`.
  """
  def generate_branch_name(task) do
    slug =
      task.title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 40)

    "mc/#{task.id}-#{slug}"
  end

  @doc """
  Creates a branch for the given task. Returns `{:ok, branch_name}`.
  If the branch already exists, returns `{:ok, branch_name}` (graceful reuse).
  """
  def create_branch(task, opts \\ []) do
    branch_name = generate_branch_name(task)
    git_opts = cmd_opts(opts)

    case System.cmd("git", ["branch", branch_name], git_opts) do
      {_, 0} ->
        {:ok, branch_name}

      {output, _code} ->
        if String.contains?(output, "already exists") do
          {:ok, branch_name}
        else
          {:error, String.trim(output)}
        end
    end
  end

  @doc """
  Checks out the given branch.
  """
  def checkout_branch(branch_name, opts \\ []) do
    git_opts = cmd_opts(opts)

    case System.cmd("git", ["checkout", branch_name], git_opts) do
      {_, 0} -> :ok
      {output, _} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Returns the current branch name.
  """
  def get_current_branch(opts \\ []) do
    git_opts = cmd_opts(opts)

    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"], git_opts) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Lists branches matching the `mc/*` pattern.
  """
  def list_branches(opts \\ []) do
    git_opts = cmd_opts(opts)

    case System.cmd("git", ["branch", "--list", "mc/*"], git_opts) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)

      {_, _} ->
        []
    end
  end

  defp cmd_opts(opts) do
    case Keyword.get(opts, :cd) do
      nil -> [stderr_to_stdout: true]
      dir -> [cd: dir, stderr_to_stdout: true]
    end
  end
end
