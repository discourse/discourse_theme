# frozen_string_literal: true

require "selenium-webdriver"

module DiscourseTheme
  class WebDriver
    def self.start_chrome(allowed_ip:, allowed_origin:)
      service = Selenium::WebDriver::Service.chrome
      options = Selenium::WebDriver::Options.chrome
      service.executable_path = Selenium::WebDriver::DriverFinder.path(options, service.class)
      service.args = ["--allowed-ips=#{allowed_ip}", "--allowed-origins=#{allowed_origin}"]
      service.launch
    end
  end
end
