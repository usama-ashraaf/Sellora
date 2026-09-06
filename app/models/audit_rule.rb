# frozen_string_literal: true

class AuditRule < ApplicationRecord
  SEVERITIES = %w[low medium high critical].freeze

  belongs_to :audit_rule_set
  has_many :audit_findings, dependent: :restrict_with_exception

  validates :rule_key, presence: true, uniqueness: { scope: :audit_rule_set_id }
  validates :severity, presence: true, inclusion: { in: SEVERITIES }
  validates :title, presence: true
end
