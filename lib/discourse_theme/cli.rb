# frozen_string_literal: true

require_relative "cli_commands/rspec"
module DiscourseTheme
  class Cli
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
        rspec DIR [OPTIONS]   - Runs the RSpec tests in the specified directory. The tests can be run using a local Discourse repository or a Docker container.
          --headful           - Runs the RSpec system type tests in headful mode. Applies to both modes.

          If specified directory has been configured to run in a Docker container, the additional options are supported.
          --rebuild           - Forces a rebuilds of Docker container.
          --verbose           - Runs the command to prepare the Docker container in verbose mode.

      Global Options:
        --reset               - Resets the configuration for the specified directory.
      USAGE

      exit 1
    end

    def run(args, &block)
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

        settings.theme_id =
          theme_id = uploader.upload_full_theme(ignore_files: ignored_migrations(theme, dir))

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
        watcher.watch(&block)
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
        DiscourseTheme::CliCommands::Rspec.run(
          settings: config[dir.split("/spec")[0]],
          dir: dir,
          args: args,
          reset: reset,
        )
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

    def ignored_migrations(theme, dir)
      return [] unless theme && Dir.exist?(File.join(dir, "migrations"))

      existing_migrations =
        theme
          .dig("theme_fields")
          &.filter_map do |theme_field|
            theme_field["name"] if theme_field["target"] == "migrations"
          end || []

      new_migrations =
        Dir["#{dir}/migrations/**/*.js"]
          .reject do |f|
            existing_migrations.any? do |existing_migration|
              File.basename(f).include?(existing_migration)
            end
          end
          .map { |f| Pathname.new(f).relative_path_from(Pathname.new(dir)).to_s }

      if !new_migrations.empty?
        options = { "Yes" => :yes, "No" => :no }

        choice = UI.select(<<~TEXT, options.keys)
        Would you like to upload and run the following pending theme migration(s): #{new_migrations.join(", ")}
        TEXT

        if options[choice] == :no
          UI.warn "Pending theme migrations have not been uploaded, run `discourse_theme upload #{dir}` if you wish to upload and run the theme migrations."
          new_migrations
        else
          []
        end
      else
        []
      end
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
