defmodule MissionControl.Orchestrator do
  alias MissionControl.Tasks

  @system_prompt """
  You are a task decomposition assistant. Given a high-level goal, break it down into \
  actionable tasks suitable for individual AI coding agents.

  Output ONLY a JSON array (no other text, no markdown fences). Each element must have:
  - "title": a short imperative task title
  - "description": detailed description of what to implement
  - "dependencies": array of task indices (0-based) this task depends on (empty if none)

  Example:
  [
    {"title": "Set up database schema", "description": "Create migrations for users table...", "dependencies": []},
    {"title": "Implement auth endpoints", "description": "Add login/register API...", "dependencies": [0]}
  ]
  """

  def system_prompt, do: @system_prompt

  def build_command(goal_text) do
    prompt = @system_prompt <> "\n\nGoal: " <> goal_text
    escaped = String.replace(prompt, "'", "'\\''")
    "echo '#{escaped}'"
  end

  def parse_proposals(raw_output) do
    case extract_json(raw_output) do
      {:ok, proposals} when is_list(proposals) ->
        validated = Enum.map(proposals, &normalize_proposal/1)

        if Enum.all?(validated, &valid_proposal?/1) do
          {:ok, validated}
        else
          {:error, :invalid_format}
        end

      {:ok, _not_a_list} ->
        {:error, :invalid_format}

      :error ->
        {:error, :invalid_json}
    end
  end

  def approve_plan(proposals) do
    tasks =
      Enum.reduce(proposals, [], fn proposal, acc ->
        attrs = %{
          title: proposal["title"],
          description: proposal["description"]
        }

        case Tasks.create_task(attrs) do
          {:ok, task} -> acc ++ [task]
          {:error, _} -> acc
        end
      end)

    {:ok, tasks}
  end

  # --- Private ---

  defp extract_json(raw_output) do
    # Try the raw output first
    case Jason.decode(String.trim(raw_output)) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, _} ->
        # Try to find JSON inside markdown fences
        case Regex.run(~r/```(?:json)?\s*\n?(.*?)\n?\s*```/s, raw_output) do
          [_, json_str] ->
            case Jason.decode(String.trim(json_str)) do
              {:ok, parsed} -> {:ok, parsed}
              {:error, _} -> try_find_array(raw_output)
            end

          nil ->
            try_find_array(raw_output)
        end
    end
  end

  defp try_find_array(raw_output) do
    # Try to find a JSON array pattern in the output
    case Regex.run(~r/\[.*\]/s, raw_output) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> :error
        end

      nil ->
        :error
    end
  end

  defp normalize_proposal(proposal) when is_map(proposal) do
    %{
      "title" => Map.get(proposal, "title"),
      "description" => Map.get(proposal, "description"),
      "dependencies" => Map.get(proposal, "dependencies", [])
    }
  end

  defp normalize_proposal(_), do: %{"title" => nil, "description" => nil, "dependencies" => []}

  defp valid_proposal?(proposal) do
    is_binary(proposal["title"]) and proposal["title"] != "" and
      is_binary(proposal["description"]) and proposal["description"] != "" and
      is_list(proposal["dependencies"])
  end
end
