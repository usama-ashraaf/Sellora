class CreateShops < ActiveRecord::Migration[8.1]
  def change
    create_table :shops do |t|
      t.string :shopify_domain, null: false
      t.text :access_token
      t.string :scope
      t.datetime :uninstalled_at

      t.timestamps
    end

    add_index :shops, :shopify_domain, unique: true
  end
end
