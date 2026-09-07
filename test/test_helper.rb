ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def with_singleton_stub(target, method_name, replacement)
      original = target.method(method_name)
      target.singleton_class.define_method(method_name, replacement)
      yield
    ensure
      target.singleton_class.define_method(method_name, original)
    end
  end
end
