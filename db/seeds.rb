# frozen_string_literal: true

# Idempotent M2 foundation seeds.
account = Accounts::EnsureDemoAccount.call
rule_set = Audit::ClothingRulesSeed.call

puts "Seeded account=#{account.name} id=#{account.id}"
puts "Seeded clothing rule set=#{rule_set.version} rules=#{rule_set.audit_rules.count} active=#{rule_set.active}"
puts "Shops scoped to demo account: #{Shop.for_account(account).count}"
