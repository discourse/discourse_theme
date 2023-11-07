# frozen_string_literal: true

require "selenium-webdriver"

module DiscourseTheme
  module CliCommands
    class Rspec
      DISCOURSE_TEST_DOCKER_CONTAINER_NAME_PREFIX = "discourse_theme_test"
      DISCOURSE_THEME_TEST_TMP_DIR = "/tmp/.discourse_theme_test"
      SELENIUM_HEADFUL_ENV = "SELENIUM_HEADLESS=0"

      class << self
        def discourse_test_docker_container_name
          "#{DISCOURSE_TEST_DOCKER_CONTAINER_NAME_PREFIX}_#{DiscourseTheme::VERSION}"
        end

        def run(settings:, dir:, args:, reset: false)
          settings.local_discourse_directory = nil if reset

          spec_path = "/spec"
          index = dir.index(spec_path)

          if index
            spec_path = dir[index..-1]
            dir = dir[0..index - 1]
          end

          spec_directory = File.join(dir, "/spec")

          unless Dir.exist?(spec_directory)
            raise DiscourseTheme::ThemeError.new "'#{spec_directory} does not exist"
          end

          configure_local_directory(settings)

          headless = !args.delete("--headful")

          if settings.local_discourse_directory.empty?
            run_tests_with_docker(
              File.basename(dir),
              spec_directory,
              spec_path,
              headless: headless,
              verbose: !!args.delete("--verbose"),
              rebuild: !!args.delete("--rebuild"),
            )
          else
            run_tests_locally(
              settings.local_discourse_directory,
              File.join(dir, spec_path),
              headless: headless,
            )
          end
        end

        private

        def execute(command:, message: nil, exit_on_error: true, stream: false)
          UI.progress(message) if message

          success = false
          output = +""

          Open3.popen2e(command) do |stdin, stdout_and_stderr, wait_thr|
            Thread.new do
              stdout_and_stderr.each do |line|
                puts line if stream
                output << line
              end
            end

            exit_status = wait_thr.value
            success = exit_status.success?

            unless success
              UI.error "Error occured while running: `#{command}`:\n\n#{output}" unless stream
              exit 1 if exit_on_error
            end
          end

          output
        end

        def run_tests_locally(local_directory, spec_path, headless: false)
          UI.progress(
            "Running RSpec tests using local Discourse repository located at '#{local_directory}'...",
          )

          Kernel.exec(
            ENV,
            "cd #{local_directory} && #{headless ? "" : SELENIUM_HEADFUL_ENV} bundle exec rspec #{spec_path}",
          )
        end

        def run_tests_with_docker(
          theme_directory_name,
          spec_directory,
          spec_path,
          headless: false,
          verbose: false,
          rebuild: false
        )
          image = "discourse/discourse_test:release"
          UI.progress("Running RSpec tests using '#{image}' Docker image...")

          unless Dir.exist?(DISCOURSE_THEME_TEST_TMP_DIR)
            FileUtils.mkdir_p DISCOURSE_THEME_TEST_TMP_DIR
          end

          # Checks if the container is running
          container_name = discourse_test_docker_container_name
          is_running = false

          if !(
               output =
                 execute(
                   command: "docker ps -a --filter name=#{container_name} --format '{{json .}}'",
                 )
             ).empty?
            is_running = JSON.parse(output)["State"] == "running"
          end
          #
          if !is_running || rebuild
            # Stop older versions of Docker container
            existing_docker_container_ids =
              execute(
                command:
                  "docker ps -a -q --filter name=#{DISCOURSE_TEST_DOCKER_CONTAINER_NAME_PREFIX}",
              ).split("\n").join(" ")

            if !existing_docker_container_ids.empty?
              execute(command: "docker stop #{existing_docker_container_ids}")
              execute(command: "docker rm -f #{existing_docker_container_ids}")
            end

            execute(
              command: <<~CMD.squeeze(" "),
              docker run -d \
                -p 31337:31337 \
                --add-host host.docker.internal:host-gateway \
                --entrypoint=/sbin/boot \
                --name=#{container_name} \
                --pull=always \
                -v #{DISCOURSE_THEME_TEST_TMP_DIR}:/tmp \
                #{image}
            CMD
              message: "Creating #{image} Docker container...",
              stream: verbose,
            )

            execute(
              command:
                "docker exec -u discourse:discourse #{container_name} ruby script/docker_test.rb --no-tests --checkout-ref origin/tests-passed",
              message: "Checking out latest Discourse source code...",
              stream: verbose,
            )

            execute(
              command:
                "docker exec -e SKIP_MULTISITE=1 -u discourse:discourse #{container_name} bundle exec rake docker:test:setup",
              message: "Setting up Discourse test environment...",
              stream: verbose,
            )

            execute(
              command: "docker exec -u discourse:discourse #{container_name} bin/ember-cli --build",
              message: "Building Ember CLI assets...",
              stream: verbose,
            )
          end

          rspec_envs = []

          if !headless
            container_ip =
              execute(
                command:
                  "docker inspect #{container_name} --format '{{.NetworkSettings.IPAddress}}'",
              ).chomp("\n")

            service =
              start_chromedriver(allowed_origin: "host.docker.internal", allowed_ip: container_ip)

            rspec_envs.push(SELENIUM_HEADFUL_ENV)
            rspec_envs.push("CAPYBARA_SERVER_HOST=0.0.0.0")
            rspec_envs.push(
              "CAPYBARA_REMOTE_DRIVER_URL=http://host.docker.internal:#{service.uri.port}",
            )
          end

          rspec_envs = rspec_envs.map { |env| "-e #{env}" }.join(" ")

          begin
            tmp_theme_directory = File.join(DISCOURSE_THEME_TEST_TMP_DIR, theme_directory_name)
            FileUtils.mkdir_p(tmp_theme_directory) if !Dir.exist?(tmp_theme_directory)
            FileUtils.cp_r(spec_directory, File.join(tmp_theme_directory))

            execute(
              command:
                "docker exec #{rspec_envs} -t -u discourse:discourse #{container_name} bundle exec rspec #{File.join("/tmp", theme_directory_name, spec_path)}".squeeze(
                  " ",
                ),
              stream: true,
            )
          ensure
            FileUtils.rm_rf(File.join(tmp_theme_directory, "/spec"))
          end
        end

        def configure_local_directory(settings)
          return if settings.local_discourse_directory_configured?

          should_configure_local_directory =
            UI.yes?(
              "Would you like to configure a local Discourse repository used to run the RSpec tests? If you select 'n', the tests will be run using a Docker container.",
            )

          if should_configure_local_directory
            local_discourse_directory =
              UI.ask("Please enter the path to the local Discourse directory:")

            unless Dir.exist?(local_discourse_directory)
              raise DiscourseTheme::ThemeError.new "'#{local_discourse_directory} does not exist"
            end

            unless File.exist?("#{local_discourse_directory}/lib/discourse.rb")
              raise DiscourseTheme::ThemeError.new "'#{local_discourse_directory} is not a Discourse repository"
            end

            settings.local_discourse_directory = local_discourse_directory
          else
            settings.local_discourse_directory = ""
          end
        end

        def start_chromedriver(allowed_ip:, allowed_origin:)
          service = Selenium::WebDriver::Service.chrome
          options = Selenium::WebDriver::Options.chrome
          service.executable_path = Selenium::WebDriver::DriverFinder.path(options, service.class)
          service.args = ["--allowed-ips=#{allowed_ip}", "--allowed-origins=#{allowed_origin}"]
          service.launch
        end
      end
    end
  end
end
