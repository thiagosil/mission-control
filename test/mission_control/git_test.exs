defmodule MissionControl.GitTest do
  use ExUnit.Case, async: true

  alias MissionControl.Git

  # Helper to create a temp git repo for each test
  defp init_tmp_repo(_context) do
    tmp_dir = Path.join(System.tmp_dir!(), "mc_git_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)

    System.cmd("git", ["commit", "--allow-empty", "-m", "init"],
      cd: tmp_dir,
      stderr_to_stdout: true
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  defp fake_task(attrs \\ %{}) do
    Map.merge(%{id: 7, title: "Add user authentication"}, attrs)
  end

  describe "generate_branch_name/1" do
    test "generates correct format" do
      task = fake_task()
      assert Git.generate_branch_name(task) == "mc/7-add-user-authentication"
    end

    test "handles special characters" do
      task = fake_task(%{title: "Fix bug #123 (urgent!)"})
      assert Git.generate_branch_name(task) == "mc/7-fix-bug-123-urgent"
    end

    test "handles uppercase" do
      task = fake_task(%{title: "Add OAuth2 Login"})
      assert Git.generate_branch_name(task) == "mc/7-add-oauth2-login"
    end

    test "truncates long titles" do
      task = fake_task(%{title: String.duplicate("very-long-title-", 10)})
      branch = Git.generate_branch_name(task)
      # "mc/<id>-" prefix + max 40 chars for slug
      slug = branch |> String.replace("mc/7-", "")
      assert String.length(slug) <= 40
    end

    test "trims trailing hyphens from slug" do
      task = fake_task(%{title: "trailing special char!"})
      branch = Git.generate_branch_name(task)
      refute String.ends_with?(branch, "-")
    end
  end

  describe "create_branch/1" do
    setup :init_tmp_repo

    test "creates a branch with correct name", %{tmp_dir: dir} do
      task = fake_task()
      assert {:ok, "mc/7-add-user-authentication"} = Git.create_branch(task, cd: dir)

      # Verify branch exists
      {output, 0} = System.cmd("git", ["branch", "--list", "mc/*"], cd: dir)
      assert output =~ "mc/7-add-user-authentication"
    end

    test "gracefully handles existing branch", %{tmp_dir: dir} do
      task = fake_task()
      assert {:ok, branch} = Git.create_branch(task, cd: dir)
      # Creating again should succeed (reuse)
      assert {:ok, ^branch} = Git.create_branch(task, cd: dir)
    end
  end

  describe "checkout_branch/1" do
    setup :init_tmp_repo

    test "checks out an existing branch", %{tmp_dir: dir} do
      task = fake_task()
      {:ok, branch} = Git.create_branch(task, cd: dir)
      assert :ok = Git.checkout_branch(branch, cd: dir)
      assert {:ok, ^branch} = Git.get_current_branch(cd: dir)
    end

    test "returns error for non-existent branch", %{tmp_dir: dir} do
      assert {:error, _reason} = Git.checkout_branch("nonexistent-branch", cd: dir)
    end
  end

  describe "get_current_branch/0" do
    setup :init_tmp_repo

    test "returns the current branch", %{tmp_dir: dir} do
      assert {:ok, branch} = Git.get_current_branch(cd: dir)
      assert branch in ["main", "master"]
    end
  end

  describe "list_branches/0" do
    setup :init_tmp_repo

    test "returns mc/* branches", %{tmp_dir: dir} do
      Git.create_branch(fake_task(%{id: 1, title: "First"}), cd: dir)
      Git.create_branch(fake_task(%{id: 2, title: "Second"}), cd: dir)

      branches = Git.list_branches(cd: dir)
      assert "mc/1-first" in branches
      assert "mc/2-second" in branches
    end

    test "returns empty list when no mc branches", %{tmp_dir: dir} do
      assert Git.list_branches(cd: dir) == []
    end
  end
end
