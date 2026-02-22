defmodule MissionControl.OrchestratorTest do
  use MissionControl.DataCase

  alias MissionControl.Orchestrator

  describe "system_prompt/0" do
    test "returns a non-empty string" do
      prompt = Orchestrator.system_prompt()
      assert is_binary(prompt)
      assert String.length(prompt) > 0
    end
  end

  describe "build_command/1" do
    test "returns a shell command string" do
      command = Orchestrator.build_command("Add user auth")
      assert is_binary(command)
      assert command =~ "Add user auth"
    end
  end

  describe "parse_proposals/1" do
    test "parses valid JSON array into proposals" do
      json = ~s([
        {"title": "Set up schema", "description": "Create migrations", "dependencies": []},
        {"title": "Add endpoints", "description": "Implement API routes", "dependencies": [0]}
      ])

      assert {:ok, proposals} = Orchestrator.parse_proposals(json)
      assert length(proposals) == 2
      assert hd(proposals)["title"] == "Set up schema"
      assert List.last(proposals)["dependencies"] == [0]
    end

    test "handles JSON embedded in markdown fences" do
      output = """
      Here are the tasks:

      ```json
      [
        {"title": "Task one", "description": "Do thing one", "dependencies": []},
        {"title": "Task two", "description": "Do thing two", "dependencies": [0]}
      ]
      ```

      That should work!
      """

      assert {:ok, proposals} = Orchestrator.parse_proposals(output)
      assert length(proposals) == 2
    end

    test "handles JSON embedded in plain markdown fences" do
      output = """
      ```
      [{"title": "Only task", "description": "The only one", "dependencies": []}]
      ```
      """

      assert {:ok, proposals} = Orchestrator.parse_proposals(output)
      assert length(proposals) == 1
    end

    test "handles JSON array embedded in surrounding text" do
      output = """
      Some preamble text
      [{"title": "Found it", "description": "Extracted from text", "dependencies": []}]
      Some trailing text
      """

      assert {:ok, proposals} = Orchestrator.parse_proposals(output)
      assert length(proposals) == 1
      assert hd(proposals)["title"] == "Found it"
    end

    test "returns error for garbage input" do
      assert {:error, :invalid_json} = Orchestrator.parse_proposals("this is not json at all")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_json} = Orchestrator.parse_proposals("")
    end

    test "returns error for JSON missing required fields" do
      json = ~s([{"title": "Has title", "dependencies": []}])

      assert {:error, :invalid_format} = Orchestrator.parse_proposals(json)
    end

    test "returns error for JSON with empty title" do
      json = ~s([{"title": "", "description": "Has desc", "dependencies": []}])

      assert {:error, :invalid_format} = Orchestrator.parse_proposals(json)
    end

    test "returns error for JSON object instead of array" do
      json = ~s({"title": "Not an array", "description": "Oops"})

      assert {:error, :invalid_format} = Orchestrator.parse_proposals(json)
    end

    test "normalizes proposals with default empty dependencies" do
      json = ~s([{"title": "No deps field", "description": "Should default to empty"}])

      assert {:ok, proposals} = Orchestrator.parse_proposals(json)
      assert hd(proposals)["dependencies"] == []
    end
  end

  describe "approve_plan/1" do
    test "creates tasks for each proposal" do
      proposals = [
        %{"title" => "First task", "description" => "Do first thing", "dependencies" => []},
        %{"title" => "Second task", "description" => "Do second thing", "dependencies" => [0]}
      ]

      assert {:ok, tasks} = Orchestrator.approve_plan(proposals)
      assert length(tasks) == 2
      assert hd(tasks).title == "First task"
      assert hd(tasks).description == "Do first thing"
      assert List.last(tasks).title == "Second task"
    end

    test "returns created tasks in order" do
      proposals = [
        %{"title" => "Alpha", "description" => "First", "dependencies" => []},
        %{"title" => "Beta", "description" => "Second", "dependencies" => []},
        %{"title" => "Gamma", "description" => "Third", "dependencies" => []}
      ]

      assert {:ok, tasks} = Orchestrator.approve_plan(proposals)
      titles = Enum.map(tasks, & &1.title)
      assert titles == ["Alpha", "Beta", "Gamma"]
    end

    test "all created tasks are in inbox column" do
      proposals = [
        %{"title" => "Inbox task", "description" => "Should be inbox", "dependencies" => []}
      ]

      assert {:ok, [task]} = Orchestrator.approve_plan(proposals)
      assert task.column == "inbox"
    end

    test "returns empty list for empty proposals" do
      assert {:ok, []} = Orchestrator.approve_plan([])
    end
  end
end
