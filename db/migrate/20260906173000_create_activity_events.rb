# frozen_string_literal: true

class CreateActivityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :shop, null: true, foreign_key: true
      t.string :event_name, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :source, null: false, default: "internal"
      t.timestamps
    end
    add_index :activity_events, [ :account_id, :occurred_at ]
    add_index :activity_events, [ :shop_id, :event_name ]
    add_index :activity_events, [ :event_name, :occurred_at ]
  end
end
