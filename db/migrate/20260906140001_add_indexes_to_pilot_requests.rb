# frozen_string_literal: true

class AddIndexesToPilotRequests < ActiveRecord::Migration[8.1]
  def change
    add_index :pilot_requests, :email unless index_exists?(:pilot_requests, :email)
    add_index :pilot_requests, :created_at unless index_exists?(:pilot_requests, :created_at)
  end
end
