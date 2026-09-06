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

  test "sellora webhook and web pixel register tasks are defined" do
    assert Rake::Task.task_defined?("sellora:register_webhooks")
    assert Rake::Task.task_defined?("sellora:register_webhooks_all")
    assert Rake::Task.task_defined?("sellora:register_web_pixel")
    assert Rake::Task.task_defined?("sellora:register_web_pixel_all")
  end
end
