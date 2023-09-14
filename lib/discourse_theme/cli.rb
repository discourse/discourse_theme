# frozen_string_literal: true

require "open3"
require "pathname"
require_relative "web_driver"

module DiscourseTheme
  class Cli
    DISCOURSE_TEST_DOCKER_CONTAINER_NAME = "discourse_theme_test"
    DISCOURSE_THEME_TEST_TMP_DIR = "/tmp/.discourse_theme_test"

    @@cli_settings_filename = File.expand_path("~/.discourse_theme")

    def self.settings_file
      @@cli_settings_filename
    end

    def self.settings_file=(filename)
      @@cli_settings_filename = filename
    end

    def usage
      puts <<~USAGE
      Usage: discourse_theme COMMAND [DIR] [OPTIONS]

      Commands:
        new DIR               - Creates a new theme in the specified directory.
        download DIR          - Downloads a theme from the server and stores it in the specified directory.
        upload DIR            - Uploads the theme from the specified directory to Discourse.
        watch DIR             - Watches the theme in the specified directory and synchronizes any changes with Discourse.
        rspec DIR [OPTIONS]   - Runs the RSpec tests in the specified directory.
          --headless          - Runs the RSpec system type tests in headless mode.
          --rebuild           - Setups the dependencies for the testing again.
          --verbose           - Runs the command in verbose mode.

      Global Options:
        --reset               - Resets the configuration for the specified directory.
      USAGE

      exit 1
    end

    def run(args)
      usage unless args[1]

      reset = !!args.delete("--reset")

      command = args[0].to_s.downcase
      dir = File.expand_path(args[1])

      config = DiscourseTheme::Config.new(self.class.settings_file)
      settings = config[dir]

      theme_id = settings.theme_id
      components = settings.components

      if command == "new"
        if Dir.exist?(dir) && !Dir.empty?(dir)
          raise DiscourseTheme::ThemeError.new "'#{dir}' is not empty"
        end
        raise DiscourseTheme::ThemeError.new "git is not installed" if !command?("git")
        raise DiscourseTheme::ThemeError.new "yarn is not installed" if !command?("yarn")

        DiscourseTheme::Scaffold.generate(dir)
        watch_theme?(args)
      elsif command == "watch"
        raise DiscourseTheme::ThemeError.new "'#{dir} does not exist" unless Dir.exist?(dir)
        client = DiscourseTheme::Client.new(dir, settings, reset: reset)

        theme_list = client.get_themes_list

        options = {}
        if theme_id && theme = theme_list.find { |t| t["id"] == theme_id }
          options["Sync with existing theme: '#{theme["name"]}' (id:#{theme_id})"] = :default
        end
        options["Create and sync with a new theme"] = :create
        options["Select a different theme"] = :select

        choice = UI.select("How would you like to sync this theme?", options.keys)

        if options[choice] == :create
          theme_id = nil
        elsif options[choice] == :select
          themes = render_theme_list(theme_list)
          choice = UI.select("Which theme would you like to sync with?", themes)
          theme_id = extract_theme_id(choice)
          theme = theme_list.find { |t| t["id"] == theme_id }
        end

        about_json =
          begin
            JSON.parse(File.read(File.join(dir, "about.json")))
          rescue StandardError
            nil
          end
        already_uploaded = !!theme
        is_component = theme&.[]("component")
        component_count = about_json&.[]("components")&.length || 0

        if !already_uploaded && !is_component && component_count > 0
          options = {}
          options["Yes"] = :sync
          options["No"] = :none
          options = options.sort_by { |_, b| b == components.to_sym ? 0 : 1 }.to_h if components
          choice = UI.select("Would you like to update child theme components?", options.keys)
          settings.components = components = options[choice].to_s
        end

        uploader =
          DiscourseTheme::Uploader.new(
            dir: dir,
            client: client,
            theme_id: theme_id,
            components: components,
          )

        UI.progress "Uploading theme from #{dir}"
        settings.theme_id = theme_id = uploader.upload_full_theme

        UI.success "Theme uploaded (id:#{theme_id})"
        UI.info "Preview: #{client.url}/?preview_theme_id=#{theme_id}"

        if client.is_theme_creator
          UI.info "Manage: #{client.url}/my/themes"
        else
          UI.info "Manage: #{client.url}/admin/customize/themes/#{theme_id}"
        end

        UI.info "Tests: #{client.url}/theme-qunit?id=#{theme_id}"

        watcher = DiscourseTheme::Watcher.new(dir: dir, uploader: uploader)
        UI.progress "Watching for changes in #{dir}..."
        watcher.watch
      elsif command == "download"
        client = DiscourseTheme::Client.new(dir, settings, reset: reset)
        downloader = DiscourseTheme::Downloader.new(dir: dir, client: client)

        FileUtils.mkdir_p dir unless Dir.exist?(dir)
        raise DiscourseTheme::ThemeError.new "'#{dir} is not empty" unless Dir.empty?(dir)

        UI.progress "Loading theme list..."
        themes = render_theme_list(client.get_themes_list)

        choice = UI.select("Which theme would you like to download?", themes)
        theme_id = extract_theme_id(choice)

        UI.progress "Downloading theme into #{dir}"

        downloader.download_theme(theme_id)
        settings.theme_id = theme_id

        UI.success "Theme downloaded"

        watch_theme?(args)
      elsif command == "upload"
        raise DiscourseTheme::ThemeError.new "'#{dir} does not exist" unless Dir.exist?(dir)
        if theme_id == 0
          raise DiscourseTheme::ThemeError.new "No theme_id is set, please sync via the 'watch' command initially"
        end
        client = DiscourseTheme::Client.new(dir, settings, reset: reset)

        theme_list = client.get_themes_list

        theme = theme_list.find { |t| t["id"] == theme_id }
        unless theme
          raise DiscourseTheme::ThemeError.new "theme_id is set, but the theme does not exist in Discourse"
        end

        uploader =
          DiscourseTheme::Uploader.new(
            dir: dir,
            client: client,
            theme_id: theme_id,
            components: components,
          )

        UI.progress "Uploading theme (id:#{theme_id}) from #{dir} "
        settings.theme_id = theme_id = uploader.upload_full_theme

        UI.success "Theme uploaded (id:#{theme_id})"
        UI.info "Preview: #{client.root}/?preview_theme_id=#{theme_id}"
        if client.is_theme_creator
          UI.info "Manage: #{client.root}/my/themes"
        else
          UI.info "Manage: #{client.root}/admin/customize/themes/#{theme_id}"
        end
      elsif command == "rspec"
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

        unless Dir.exist?(DISCOURSE_THEME_TEST_TMP_DIR)
          FileUtils.mkdir_p DISCOURSE_THEME_TEST_TMP_DIR
        end

        # Checks if the container is running
        container_name = DISCOURSE_TEST_DOCKER_CONTAINER_NAME
        is_running = false
        container_exists = false

        if !(
             output =
               execute(
                 command: "docker ps -a --filter name=#{container_name} --format '{{json .}}'",
               )
           ).empty?
          container_exists = true
          is_running = JSON.parse(output)["State"] == "running"
        end

        basename = Pathname.new(dir).basename.to_s
        verbose = !!args.delete("--verbose")
        headless = !!args.delete("--headless")

        if !is_running || args.delete("--rebuild")
          if container_exists
            execute(command: "docker stop #{container_name}")
            execute(command: "docker rm -f #{container_name}")
          end

          execute(
            command: <<~CMD.squeeze(" "),
              docker run -d \
                -p 31337:31337 \
                --add-host host.docker.internal:host-gateway \
                --entrypoint=/sbin/boot \
                --name=#{container_name} \
                -v #{DISCOURSE_THEME_TEST_TMP_DIR}:/tmp \
                discourse/discourse_test:release
            CMD
            message: "Creating discourse/discourse_test:release Docker container...",
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

        if headless
          WebDriver.start(browser: :chrome)

          rspec_envs.push("SELENIUM_HEADLESS=0")
          rspec_envs.push("CAPYBARA_SERVER_HOST=0.0.0.0")
          rspec_envs.push("CAPYBARA_REMOTE_DRIVER_URL=http://host.docker.internal:9515")
        end

        rspec_envs = rspec_envs.map { |env| "-e #{env}" }.join(" ")

        begin
          theme_spec_directory = File.join(dir, "/spec")
          tmp_theme_directory = File.join(DISCOURSE_THEME_TEST_TMP_DIR, basename)
          FileUtils.mkdir_p(tmp_theme_directory) if !Dir.exist?(tmp_theme_directory)
          FileUtils.cp_r(theme_spec_directory, File.join(tmp_theme_directory))

          execute(
            command:
              "docker exec #{rspec_envs} -t -u discourse:discourse #{container_name} bundle exec rspec #{File.join("/tmp", basename, spec_path)}".squeeze(
                " ",
              ),
            stream: true,
          )
        ensure
          FileUtils.rm_rf(File.join(tmp_theme_directory, "/spec"))
        end
      else
        usage
      end

      UI.progress "Exiting..."
    rescue DiscourseTheme::ThemeError => e
      UI.error "#{e.message}"
    rescue Interrupt, TTY::Reader::InputInterrupt => e
      UI.error "Interrupted"
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

    def command?(cmd)
      exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
      ENV["PATH"]
        .split(File::PATH_SEPARATOR)
        .each do |path|
          exts.each do |ext|
            exe = File.join(path, "#{cmd}#{ext}")
            return true if File.executable?(exe) && !File.directory?(exe)
          end
        end

      false
    end

    def watch_theme?(args)
      if UI.yes?("Would you like to start 'watching' this theme?")
        args[0] = "watch"
        UI.progress "Running discourse_theme #{args.join(" ")}"
        run(args)
      end
    end

    def render_theme_list(themes)
      themes
        .sort_by { |t| t["updated_at"] }
        .reverse
        .map { |theme| "#{theme["name"]} (id:#{theme["id"]})" }
    end

    def extract_theme_id(rendered_name)
      /\(id:([0-9]+)\)$/.match(rendered_name)[1].to_i
    end
  end
end
