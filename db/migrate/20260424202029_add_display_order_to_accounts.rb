class AddDisplayOrderToAccounts < ActiveRecord::Migration[7.2]
  def up
    add_column :accounts, :display_order, :integer, null: false, default: 0

    # Seed with gaps so reorders later don't need to shuffle everything.
    execute <<~SQL
      WITH ordered AS (
        SELECT id, (ROW_NUMBER() OVER (PARTITION BY family_id ORDER BY name)) * 10 AS pos
        FROM accounts
      )
      UPDATE accounts SET display_order = ordered.pos
      FROM ordered WHERE accounts.id = ordered.id;
    SQL

    add_index :accounts, [ :family_id, :display_order ]
  end

  def down
    remove_index :accounts, [ :family_id, :display_order ]
    remove_column :accounts, :display_order
  end
end
