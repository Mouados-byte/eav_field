# frozen_string_literal: true

module EavField
  class Railtie < Rails::Railtie
    generators do
      require "generators/eav_field/install/install_generator"
      require "generators/eav_field/upgrade/upgrade_generator"
    end
  end
end
