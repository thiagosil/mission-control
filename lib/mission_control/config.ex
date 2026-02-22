defmodule MissionControl.Config do
  use GenServer

  @defaults %{
    agent: %{
      backend: "claude",
      auto_accept: true,
      command: nil,
      command_template: nil
    }
  }

  @known_backends %{
    "claude" => %{
      accept: ~s(claude --dangerously-skip-permissions -p "{prompt}"),
      no_accept: ~s(claude -p "{prompt}")
    },
    "codex" => %{
      accept: ~s(codex --auto-approve "{prompt}"),
      no_accept: ~s(codex "{prompt}")
    }
  }

  # --- Client API ---

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def agent_config do
    GenServer.call(__MODULE__, :agent_config)
  end

  def agent_backend do
    agent_config().backend
  end

  def agent_command_template do
    config = agent_config()
    resolve_template(config)
  end

  def interpolate_command(template, vars) do
    Enum.reduce(vars, template, fn {key, value}, acc ->
      String.replace(acc, "{#{key}}", value)
    end)
  end

  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    toml_path = Keyword.get(opts, :toml_path, "mission_control.toml")

    # Overrides can be passed directly via opts (for isolated test instances)
    # or via Application config (for the app-level supervised instance)
    overrides =
      case Keyword.fetch(opts, :overrides) do
        {:ok, val} ->
          val

        :error ->
          app_config = Application.get_env(:mission_control, __MODULE__, [])
          Keyword.get(app_config, :overrides)
      end

    state = %{
      toml_path: toml_path,
      overrides: overrides,
      config: load_config(toml_path, overrides)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:agent_config, _from, state) do
    {:reply, state.config.agent, state}
  end

  def handle_call(:reload, _from, state) do
    new_config = load_config(state.toml_path, state.overrides)
    {:reply, :ok, %{state | config: new_config}}
  end

  # --- Config Loading ---

  defp load_config(_toml_path, overrides) when is_map(overrides) do
    deep_merge(@defaults, overrides)
  end

  defp load_config(toml_path, _overrides) do
    toml_config = load_toml(toml_path)
    env_config = load_env()

    @defaults
    |> deep_merge(toml_config)
    |> deep_merge(env_config)
  end

  defp load_toml(path) do
    case Toml.decode_file(path) do
      {:ok, data} -> normalize_toml(data)
      {:error, _} -> %{}
    end
  end

  defp normalize_toml(data) do
    agent = Map.get(data, "agent", %{})

    agent_config =
      %{}
      |> put_if_present(:backend, Map.get(agent, "backend"))
      |> put_if_present(:auto_accept, Map.get(agent, "auto_accept"))
      |> put_if_present(:command, Map.get(agent, "command"))
      |> put_if_present(:command_template, Map.get(agent, "command_template"))

    if agent_config == %{}, do: %{}, else: %{agent: agent_config}
  end

  defp load_env do
    agent_config =
      %{}
      |> put_if_present(:backend, System.get_env("MC_AGENT_BACKEND"))
      |> put_if_present(:auto_accept, parse_bool_env("MC_AGENT_AUTO_ACCEPT"))
      |> put_if_present(:command, System.get_env("MC_AGENT_COMMAND"))
      |> put_if_present(:command_template, System.get_env("MC_AGENT_COMMAND_TEMPLATE"))

    if agent_config == %{}, do: %{}, else: %{agent: agent_config}
  end

  defp parse_bool_env(var) do
    case System.get_env(var) do
      "true" -> true
      "1" -> true
      "false" -> false
      "0" -> false
      _ -> nil
    end
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  # --- Template Resolution ---

  defp resolve_template(%{command_template: template}) when is_binary(template), do: template

  defp resolve_template(%{backend: backend, auto_accept: auto_accept} = config) do
    base_command = config.command || backend

    case Map.get(@known_backends, backend) do
      %{accept: accept_cmd, no_accept: no_accept_cmd} ->
        if config.command do
          # Custom command but known backend — replace the executable in the template
          template = if auto_accept, do: accept_cmd, else: no_accept_cmd
          String.replace(template, backend, base_command, global: false)
        else
          if auto_accept, do: accept_cmd, else: no_accept_cmd
        end

      nil ->
        ~s(#{base_command} "{prompt}")
    end
  end

  defp deep_merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn
      _key, base_val, override_val when is_map(base_val) and is_map(override_val) ->
        deep_merge(base_val, override_val)

      _key, _base_val, override_val ->
        override_val
    end)
  end

  defp deep_merge(base, _override), do: base
end
