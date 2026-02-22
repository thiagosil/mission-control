defmodule MissionControl.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :type, :string, null: false
      add :message, :string, null: false
      add :metadata, :map, default: %{}
      add :agent_id, references(:agents, on_delete: :nilify_all)
      add :task_id, references(:tasks, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:type])
    create index(:events, [:agent_id])
    create index(:events, [:task_id])
    create index(:events, [:inserted_at])
  end
end
