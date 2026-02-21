defmodule MissionControl.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :title, :string, null: false
      add :description, :text
      add :column, :string, null: false, default: "inbox"
      add :agent_id, references(:agents, on_delete: :nilify_all)
      add :priority, :string, null: false, default: "normal"
      add :tags, :string, default: "[]"
      add :branch_name, :string
      add :dependencies, :string, default: "[]"

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:column])
    create index(:tasks, [:agent_id])
  end
end
