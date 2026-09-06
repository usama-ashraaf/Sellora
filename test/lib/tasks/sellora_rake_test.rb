# frozen_string_literal: true

require "test_helper"
require "rake"

class SelloraRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  test "sellora sync and parity tasks are defined" do
    assert Rake::Task.task_defined?("sellora:sync_catalog")
    assert Rake::Task.task_defined?("sellora:sync_catalog_all")
    assert Rake::Task.task_defined?("sellora:catalog_parity")
  end
end
