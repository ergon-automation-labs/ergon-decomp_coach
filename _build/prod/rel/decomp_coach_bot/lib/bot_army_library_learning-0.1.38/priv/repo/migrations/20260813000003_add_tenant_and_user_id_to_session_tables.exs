defmodule BotArmyLearning.Repo.Migrations.AddTenantAndUserIdToSessionTables do
  use Ecto.Migration

  @tables [:learning_sessions, :learning_reviews, :learning_snoozes]

  def up do
    default_tenant_id = "00000000-0000-0000-0000-000000000001"

    for table <- @tables do
      alter table(table) do
        add(:tenant_id, :uuid, null: true)
        add(:user_id, :uuid, null: true)
      end

      create(index(table, [:tenant_id]))
      create(index(table, [:user_id]))

      execute(
        "UPDATE #{table} SET tenant_id = '#{default_tenant_id}'::uuid WHERE tenant_id IS NULL"
      )

      execute("UPDATE #{table} SET user_id = '#{default_tenant_id}'::uuid WHERE user_id IS NULL")

      execute("ALTER TABLE #{table} ALTER COLUMN tenant_id SET NOT NULL")
      execute("ALTER TABLE #{table} ALTER COLUMN user_id SET NOT NULL")
    end
  end

  def down do
    for table <- @tables do
      drop(index(table, [:tenant_id]))
      drop(index(table, [:user_id]))

      alter table(table) do
        remove(:tenant_id)
        remove(:user_id)
      end
    end
  end
end
