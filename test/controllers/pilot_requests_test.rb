require "test_helper"

class PilotRequestsTest < ActionDispatch::IntegrationTest
  test "valid submission is durably stored before a 303 confirmation and sends no email" do
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      assert_difference "PilotRequest.count", 1 do
        post pilot_requests_path, params: { pilot_request: valid_attributes.merge(email: " OWNER@EXAMPLE.COM ") }
      end
    end
    assert_response :see_other
    assert_redirected_to root_path(anchor: "pilot")
    assert_equal "owner@example.com", PilotRequest.last.email
    assert_equal "no-store", response.headers["Cache-Control"]
    follow_redirect!
    assert_select ".form-notice", text: /Your pilot request has been saved/
    assert_select ".pilot-form", count: 0
  end

  test "invalid submission retains values and gives accessible errors without saving" do
    assert_no_difference "PilotRequest.count" do
      post pilot_requests_path, params: { pilot_request: valid_attributes.merge(email: "invalid") }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors[role=alert]", text: /hasn't been saved/
    assert_select "input[name='pilot_request[email]'][value=invalid][aria-invalid=true]"
    assert_select "input[name='pilot_request[name]'][value='Review Brand']"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "invalid store URL cannot be submitted through a handcrafted request" do
    assert_no_difference "PilotRequest.count" do
      post pilot_requests_path, params: { pilot_request: valid_attributes.merge(store_url: "https://user:password@example.com") }
    end
    assert_response :unprocessable_entity
    assert_select ".form-notice", count: 0
  end

  test "submitted HTML is escaped on validation failure" do
    post pilot_requests_path, params: { pilot_request: valid_attributes.merge(name: '<script>alert("xss")</script>', email: "invalid") }
    assert_response :unprocessable_entity
    assert_select "script", text: 'alert("xss")', count: 0
    assert_includes response.body, "&lt;script&gt;"
  end

  test "unexpected record attributes cannot be mass assigned" do
    post pilot_requests_path, params: { pilot_request: valid_attributes.merge(id: 987654321, created_at: "2000-01-01") }
    assert_response :see_other
    assert_not_equal 987654321, PilotRequest.last.id
    assert_operator PilotRequest.last.created_at, :>, 1.minute.ago
  end

  test "storage failure returns 503 without success or sensitive error text" do
    request = PilotRequest.new(valid_attributes)
    failing_save = -> { raise ActiveRecord::ConnectionNotEstablished, "private database detail" }
    with_replaced_method(PilotRequest, :new, request) do
      with_replaced_method(request, :save, failing_save) do
        post pilot_requests_path, params: { pilot_request: valid_attributes }
      end
    end
    assert_response :service_unavailable
    assert_select ".form-errors", text: /couldn't save your request/
    assert_select ".form-notice", count: 0
    assert_not_includes response.body, "private database detail"
  end

  test "database statement failure also returns a truthful retry response" do
    request = PilotRequest.new(valid_attributes)
    with_replaced_method(PilotRequest, :new, request) do
      with_replaced_method(request, :save, -> { raise ActiveRecord::StatementInvalid, "private row data" }) do
        post pilot_requests_path, params: { pilot_request: valid_attributes }
      end
    end
    assert_response :service_unavailable
    assert_select ".form-notice", count: 0
    assert_not_includes response.body, "private row data"
  end

  test "rate limit rejects the sixth request and resets after its window" do
    store = ActiveSupport::Cache::MemoryStore.new
    with_replaced_method(PilotRequestsController.cache_store, :increment, ->(key, amount, **options) { store.increment(key, amount, **options) }) do
      5.times do
        post pilot_requests_path, params: { pilot_request: valid_attributes.merge(email: "invalid") }
        assert_response :unprocessable_entity
      end
      assert_no_difference "PilotRequest.count" do
        post pilot_requests_path, params: { pilot_request: valid_attributes }
      end
      assert_response :too_many_requests
      assert_equal "600", response.headers["Retry-After"]
      assert_select ".form-errors", text: /wait 10 minutes/
      travel 11.minutes do
        post pilot_requests_path, params: { pilot_request: valid_attributes }
        assert_response :see_other
      end
    end
  end

  test "CSRF protection rejects a POST without a token when enabled" do
    original = ApplicationController.allow_forgery_protection
    ApplicationController.allow_forgery_protection = true
    assert_no_difference "PilotRequest.count" do
      post pilot_requests_path, params: { pilot_request: valid_attributes }
    end
    assert_response :unprocessable_entity
  ensure
    ApplicationController.allow_forgery_protection = original
  end

  test "submitted fields are filtered in request parameters and SQL bind logs" do
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    original_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = logger
    ActiveRecord::Base.connection.unprepared_statement do
      post pilot_requests_path, params: { pilot_request: valid_attributes }
    end
    assert_response :see_other
    values = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(valid_attributes)
    assert values.values.all? { |value| value == "[FILTERED]" }
    valid_attributes.values.each { |value| assert_not_includes output.string, value }
  ensure
    ActiveRecord::Base.logger = original_logger
  end

  test "model initialization failure still returns an editable form with a retry error" do
    with_replaced_method(PilotRequest, :new, ->(*) { raise ActiveRecord::ConnectionNotEstablished }) do
      post pilot_requests_path, params: { pilot_request: valid_attributes }
    end
    assert_response :service_unavailable
    assert_select ".form-errors", text: /couldn't save your request/
    assert_select "input[name='pilot_request[name]'][value='Review Brand']"
    assert_select ".form-notice", count: 0
  end

  test "homepage renders without initializing an Active Record submission" do
    with_replaced_method(PilotRequest, :new, ->(*) { raise ActiveRecord::ConnectionNotEstablished }) do
      get root_path
    end
    assert_response :success
    assert_select ".pilot-form"
  end

  private

  def with_replaced_method(object, name, replacement)
    original = object.method(name)
    object.define_singleton_method(name) do |*args, **options, &block|
      replacement.respond_to?(:call) ? replacement.call(*args, **options, &block) : replacement
    end
    yield
  ensure
    object.define_singleton_method(name, original)
  end

  def valid_attributes
    { name: "Review Brand", email: "owner@example.com", store_url: "https://example.com", platform: "Shopify" }
  end
end
