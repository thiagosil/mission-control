defmodule MissionControl.Git.Sandbox do
  @moduledoc """
  A no-op Git implementation for tests.
  Returns successful results without running real git commands,
  so tests don't depend on the working tree's git state.
  """

  def generate_branch_name(task), do: MissionControl.Git.generate_branch_name(task)

  def create_branch(task, _opts \\ []) do
    {:ok, generate_branch_name(task)}
  end

  def checkout_branch(_branch_name, _opts \\ []), do: :ok
end
