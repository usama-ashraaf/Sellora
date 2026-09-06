# frozen_string_literal: true

class CreateAccountsUsersMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :accounts, :name

    create_table :users do |t|
      t.string :email, null: false
      t.string :name
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :memberships do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :email, null: false
      t.string :role, null: false, default: "member"
      t.timestamps
    end
    add_index :memberships, [ :account_id, :email ], unique: true
    add_index :memberships, [ :account_id, :role ]
  end
end
