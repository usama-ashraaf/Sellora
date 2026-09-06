class CreatePilotRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :pilot_requests do |t|
      t.string :name, null: false, limit: 100
      t.string :email, null: false, limit: 254
      t.string :store_url, null: false, limit: 2048
      t.string :platform, null: false, limit: 40
      t.timestamps
    end
  end
end
