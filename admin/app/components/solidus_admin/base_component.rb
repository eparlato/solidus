# frozen_string_literal: true

module SolidusAdmin
  # BaseComponent is the base class for all components in Solidus Admin.
  class BaseComponent < ViewComponent::Base
    def container
      SolidusAdmin::Container
    end
  end
end
