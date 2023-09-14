# frozen_string_literal: true

require "selenium-webdriver"

module DiscourseTheme
  class WebDriver
    def self.start(browser: :chrome)
      case browser
      when :chrome
        service = Selenium::WebDriver::Service.chrome
        options = Selenium::WebDriver::Options.chrome
        service.executable_path = Selenium::WebDriver::DriverFinder.path(options, service.class)
        service.args = %w[--whitelisted-ips --allowed-origins=*]
        service.launch
      else
        raise "Unsupported browser: #{browser}"
      end
    end
  end
end