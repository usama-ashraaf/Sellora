# frozen_string_literal: true

class Account < ApplicationRecord
  DEMO_NAME = "Sellora Demo"

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :shops, dependent: :nullify
  has_many :autopilot_runs, dependent: :destroy
  has_many :audit_findings, dependent: :destroy
  has_many :activity_events, dependent: :destroy

  validates :name, presence: true

  def self.demo
    find_by(name: DEMO_NAME)
  end

  def self.demo!
    find_or_create_by!(name: DEMO_NAME)
  end
end
