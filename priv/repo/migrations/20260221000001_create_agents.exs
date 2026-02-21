defmodule MissionControl.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents) do
      add :name, :string, null: false
      add :role, :string
      add :status, :string, null: false, default: "stopped"
      add :config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end
  end
end
