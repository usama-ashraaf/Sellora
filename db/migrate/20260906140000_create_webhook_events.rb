# frozen_string_literal: true

class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_events do |t|
      t.string :shopify_domain, null: false
      t.string :topic, null: false
      t.string :event_key, null: false
      t.datetime :processed_at, null: false

      t.timestamps
    end

    add_index :webhook_events, :event_key, unique: true
    add_index :webhook_events, [ :shopify_domain, :topic ]
  end
end
