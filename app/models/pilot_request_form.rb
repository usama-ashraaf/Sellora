class PilotRequestForm
  include ActiveModel::Model

  attr_accessor :name, :email, :store_url, :platform
end
