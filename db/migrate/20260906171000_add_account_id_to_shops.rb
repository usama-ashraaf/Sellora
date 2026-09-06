# frozen_string_literal: true

class AddAccountIdToShops < ActiveRecord::Migration[8.1]
  def up
    add_reference :shops, :account, null: true, foreign_key: true

    say_with_time "backfill shops onto Sellora Demo account" do
      account_id = select_value("SELECT id FROM accounts WHERE name = 'Sellora Demo' ORDER BY id ASC LIMIT 1")
      unless account_id
        execute("INSERT INTO accounts (name, created_at, updated_at) VALUES ('Sellora Demo', NOW(), NOW())")
        account_id = select_value("SELECT id FROM accounts WHERE name = 'Sellora Demo' ORDER BY id ASC LIMIT 1")
      end

      execute(ActiveRecord::Base.sanitize_sql_array([
        "UPDATE shops SET account_id = ? WHERE account_id IS NULL",
        account_id
      ]))
    end
  end

  def down
    remove_reference :shops, :account, foreign_key: true
  end
end
