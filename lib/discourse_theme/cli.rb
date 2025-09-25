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

    def self.command?(cmd)
      system "which", cmd, out: File::NULL, err: File::NULL
    end

    def usage
      puts <<~USAGE
      Usage: discourse_theme COMMAND [DIR] [OPTIONS]

      Commands:
        new DIR               - Creates a new theme in the specified directory.
        download DIR          - Downloads a theme from the server and stores it in the specified directory.
        upload DIR            - Uploads the theme from the specified directory to Discourse.
        watch DIR             - Watches the theme in the specified directory and synchronizes any changes with Discourse.
                              If multiple sites are configured, you'll be prompted to select which site to watch.
        sites DIR             - Manages multiple site configurations for a directory.
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

    def run(args)
      if args.delete("--version")
        puts VERSION
        return
      end

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
        raise DiscourseTheme::ThemeError.new "git is not installed" if !Cli.command?("git")

        DiscourseTheme::Scaffold.generate(dir, name: args[1])
        watch_theme?(args)
      elsif command == "watch"
        raise DiscourseTheme::ThemeError.new "'#{dir} does not exist" unless Dir.exist?(dir)
        
        selected_site = DiscourseTheme::SiteSelector.select_site(settings, dir)
        
        if selected_site.nil?
          client = DiscourseTheme::Client.new(dir, settings, reset: reset)
          theme_id = settings.theme_id
          components = settings.components
        else
          site_config = settings.site_config(selected_site)
          client = DiscourseTheme::Client.new(dir, settings, reset: reset, url: site_config["url"])
          theme_id = site_config["theme_id"]
          components = site_config["components"]
          
          UI.info "Watching site: #{selected_site} (#{site_config['url']})"
        end

        theme_list = client.get_themes_list

        options = {}

        if theme_id && theme_id != 0 && theme = theme_list.find { |t| t["id"] == theme_id }
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

        theme_id = uploader.upload_full_theme(skip_migrations: skip_migrations(theme, dir))

        if selected_site
          site_config = settings.site_config(selected_site)
          site_config["theme_id"] = theme_id
          settings.add_site(selected_site, url: site_config["url"], theme_id: theme_id, components: components)
        else
          settings.theme_id = theme_id
          settings.components = components if components
        end

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
      elsif command == "sites"
        manage_sites(dir, settings)
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

    def skip_migrations(theme, dir)
      return true unless theme && Dir.exist?(File.join(dir, "migrations"))

      migrated_migrations =
        theme
          .dig("theme_fields")
          &.filter_map do |theme_field|
            if theme_field["target"] == "migrations" && theme_field["migrated"] == true
              theme_field["name"]
            end
          end || []

      pending_migrations =
        Dir["#{dir}/migrations/**/*.js"]
          .reject do |f|
            migrated_migrations.any? do |existing_migration|
              File.basename(f).include?(existing_migration)
            end
          end
          .map { |f| Pathname.new(f).relative_path_from(Pathname.new(dir)).to_s }

      return true if pending_migrations.empty?

      options = { "No" => :no, "Yes" => :yes }

      choice = UI.select(<<~TEXT, options.keys)
        Would you like to run the following pending theme migration(s): #{pending_migrations.join(", ")}
          Select 'No' if you are in the midst of adding or modifying theme migration(s).
        TEXT

      if options[choice] == :no
        UI.warn "Pending theme migrations have not been run, run `discourse_theme upload #{dir}` if you wish to run the theme migrations."
        true
      else
        false
      end
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

    def manage_sites(dir, settings)
      raise DiscourseTheme::ThemeError.new "'#{dir} does not exist" unless Dir.exist?(dir)
      
      loop do
        options = {}
        
        if settings.has_multiple_sites?
          settings.site_names.each do |site_name|
            site_config = settings.site_config(site_name)
            url = site_config["url"]
            theme_id = site_config["theme_id"]
            display_name = "#{site_name} (#{url}"
            display_name += ", theme: #{theme_id}" if theme_id && theme_id != 0
            display_name += ")"
            options[display_name] = "view_#{site_name}"
          end
          options["Add a new site"] = :add
          options["Remove a site"] = :remove if settings.site_names.any?
        else
          options["Add your first site"] = :add
        end
        
        options["Exit"] = :exit
        
        choice = UI.select("Site Management - #{File.basename(dir)}", options.keys)
        action = options[choice]
        
        if action == :exit
          break
        elsif action == :add
          DiscourseTheme::SiteSelector.configure_new_site(settings, dir)
        elsif action == :remove
          remove_site(settings)
        elsif action.to_s.start_with?("view_")
          site_name = action.to_s.sub("view_", "")
          view_site(settings, site_name)
        end
      end
    end

    def remove_site(settings)
      return unless settings.has_multiple_sites?
      
      sites = settings.site_names
      choice = UI.select("Which site would you like to remove?", sites + ["Cancel"])
      
      if choice != "Cancel" && sites.include?(choice)
        if UI.yes?("Are you sure you want to remove site '#{choice}'?")
          settings.remove_site(choice)
          UI.success "Site '#{choice}' has been removed."
        end
      end
    end

    def view_site(settings, site_name)
      site_config = settings.site_config(site_name)
      
      UI.info "\nSite: #{site_name}"
      UI.info "URL: #{site_config['url']}"
      UI.info "Theme ID: #{site_config['theme_id'] || 'Not set'}"
      UI.info "Components: #{site_config['components'] || 'Default'}"
      
      if UI.yes?("\nWould you like to start watching this site?")
        UI.info "Use 'discourse_theme watch #{File.basename(settings.filename.gsub('/.discourse_theme', ''))}' and select this site."
      end
    end
  end
end
