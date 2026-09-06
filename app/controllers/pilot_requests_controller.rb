class PilotRequestsController < ApplicationController
  before_action :prevent_caching
  rate_limit to: 5, within: 10.minutes, only: :create, with: :too_many_requests

  def create
    @pilot_request = PilotRequestForm.new(pilot_request_params)

    record = PilotRequest.new(pilot_request_params)

    if ActiveRecord::Base.logger.silence { record.save }
      redirect_to root_path(anchor: "pilot"), status: :see_other,
        notice: "Your pilot request has been saved. This registers your interest; it doesn't connect your store or guarantee a place."
    else
      @pilot_request.errors.merge!(record.errors)
      render "marketing/show", status: :unprocessable_entity
    end
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid => error
    Rails.logger.error("Pilot request storage failed (#{error.class.name}); request_id=#{request.request_id}")
    @pilot_request.errors.add(:base, "We couldn't save your request. Please try again in a moment.")
    render "marketing/show", status: :service_unavailable
  end

  private

  def pilot_request_params
    params.expect(pilot_request: [ :name, :email, :store_url, :platform ])
  end

  def prevent_caching
    response.headers["Cache-Control"] = "no-store"
  end

  def too_many_requests
    @pilot_request = PilotRequestForm.new(pilot_request_params)
    @pilot_request.errors.add(:base, "Too many requests. Please wait 10 minutes before trying again.")
    response.headers["Retry-After"] = "600"
    render "marketing/show", status: :too_many_requests
  end
end
