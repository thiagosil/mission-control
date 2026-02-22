defmodule MissionControl.ConfigTest do
  use ExUnit.Case, async: false

  alias MissionControl.Config

  # Helper to start an isolated (unnamed) Config process that ignores app-level overrides
  defp start_isolated!(opts, id) do
    opts =
      opts
      |> Keyword.put(:name, nil)
      |> Keyword.put_new(:overrides, nil)

    start_supervised!({Config, opts}, id: id)
  end

  describe "test environment defaults" do
    test "agent_backend returns test backend" do
      assert Config.agent_backend() == "test"
    end

    test "agent_command_template returns test command" do
      assert Config.agent_command_template() == "echo '[agent] test output'"
    end

    test "agent_config returns full agent map" do
      config = Config.agent_config()
      assert config.backend == "test"
      assert config.command_template == "echo '[agent] test output'"
    end
  end

  describe "interpolate_command/2" do
    test "replaces {prompt} placeholder" do
      template = ~s(claude -p "{prompt}")
      result = Config.interpolate_command(template, %{"prompt" => "do something"})
      assert result == ~s(claude -p "do something")
    end

    test "replaces multiple placeholders" do
      template = ~s({backend} --flag "{prompt}")
      result = Config.interpolate_command(template, %{"prompt" => "hello", "backend" => "tool"})
      assert result == ~s(tool --flag "hello")
    end

    test "returns template unchanged when no matching placeholders" do
      template = ~s(echo "hello")
      assert Config.interpolate_command(template, %{"prompt" => "x"}) == template
    end
  end

  describe "isolated GenServer with no TOML and no env" do
    test "uses default values" do
      pid = start_isolated!([toml_path: "nonexistent.toml"], :isolated_config)
      config = GenServer.call(pid, :agent_config)
      assert config.backend == "claude"
      assert config.auto_accept == true
      assert config.command == nil
      assert config.command_template == nil
    end
  end

  describe "TOML file loading" do
    setup do
      toml_path =
        Path.join(
          System.tmp_dir!(),
          "test_config_#{System.unique_integer([:positive])}.toml"
        )

      on_exit(fn -> File.rm(toml_path) end)
      {:ok, toml_path: toml_path}
    end

    test "loads backend from TOML", %{toml_path: toml_path} do
      File.write!(toml_path, """
      [agent]
      backend = "codex"
      """)

      pid = start_isolated!([toml_path: toml_path], :toml_test)
      config = GenServer.call(pid, :agent_config)
      assert config.backend == "codex"
      assert config.auto_accept == true
    end

    test "loads all agent settings from TOML", %{toml_path: toml_path} do
      File.write!(toml_path, """
      [agent]
      backend = "codex"
      auto_accept = false
      command_template = "my-tool '{prompt}'"
      """)

      pid = start_isolated!([toml_path: toml_path], :toml_full)
      config = GenServer.call(pid, :agent_config)
      assert config.backend == "codex"
      assert config.auto_accept == false
      assert config.command_template == "my-tool '{prompt}'"
    end
  end

  describe "env var overrides" do
    setup do
      on_exit(fn ->
        System.delete_env("MC_AGENT_BACKEND")
        System.delete_env("MC_AGENT_AUTO_ACCEPT")
        System.delete_env("MC_AGENT_COMMAND")
        System.delete_env("MC_AGENT_COMMAND_TEMPLATE")
      end)

      :ok
    end

    test "MC_AGENT_BACKEND overrides default" do
      System.put_env("MC_AGENT_BACKEND", "custom-cli")
      pid = start_isolated!([toml_path: "nonexistent.toml"], :env_backend)
      config = GenServer.call(pid, :agent_config)
      assert config.backend == "custom-cli"
    end

    test "MC_AGENT_AUTO_ACCEPT=false overrides default" do
      System.put_env("MC_AGENT_AUTO_ACCEPT", "false")
      pid = start_isolated!([toml_path: "nonexistent.toml"], :env_accept)
      config = GenServer.call(pid, :agent_config)
      assert config.auto_accept == false
    end

    test "MC_AGENT_COMMAND_TEMPLATE overrides everything" do
      System.put_env("MC_AGENT_COMMAND_TEMPLATE", "custom-tool '{prompt}'")
      pid = start_isolated!([toml_path: "nonexistent.toml"], :env_template)
      config = GenServer.call(pid, :agent_config)
      assert config.command_template == "custom-tool '{prompt}'"
    end
  end

  describe "priority: env > TOML > default" do
    setup do
      toml_path =
        Path.join(
          System.tmp_dir!(),
          "priority_#{System.unique_integer([:positive])}.toml"
        )

      on_exit(fn ->
        File.rm(toml_path)
        System.delete_env("MC_AGENT_BACKEND")
      end)

      {:ok, toml_path: toml_path}
    end

    test "env var beats TOML", %{toml_path: toml_path} do
      File.write!(toml_path, """
      [agent]
      backend = "codex"
      """)

      System.put_env("MC_AGENT_BACKEND", "from-env")
      pid = start_isolated!([toml_path: toml_path], :priority_env)
      config = GenServer.call(pid, :agent_config)
      assert config.backend == "from-env"
    end

    test "TOML beats default", %{toml_path: toml_path} do
      File.write!(toml_path, """
      [agent]
      backend = "codex"
      """)

      pid = start_isolated!([toml_path: toml_path], :priority_toml)
      config = GenServer.call(pid, :agent_config)
      assert config.backend == "codex"
    end
  end

  describe "backend-specific template resolution" do
    test "claude with auto_accept produces correct template" do
      pid = start_isolated!([toml_path: "nonexistent.toml"], :claude_accept)
      config = GenServer.call(pid, :agent_config)
      assert config.backend == "claude"
      assert config.auto_accept == true
    end

    test "claude without auto_accept produces correct template" do
      toml_path =
        Path.join(
          System.tmp_dir!(),
          "claude_no_accept_#{System.unique_integer([:positive])}.toml"
        )

      File.write!(toml_path, """
      [agent]
      backend = "claude"
      auto_accept = false
      """)

      on_exit(fn -> File.rm(toml_path) end)

      pid = start_isolated!([toml_path: toml_path], :claude_no_accept)
      config = GenServer.call(pid, :agent_config)
      assert config.backend == "claude"
      assert config.auto_accept == false
    end
  end

  describe "reload/0" do
    test "picks up new config after reload" do
      assert :ok = Config.reload()
      assert Config.agent_backend() == "test"
    end
  end
end
