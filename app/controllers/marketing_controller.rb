class MarketingController < ApplicationController
  def show
    response.headers["Cache-Control"] = "no-store"
    @pilot_request = PilotRequestForm.new
  end
end
