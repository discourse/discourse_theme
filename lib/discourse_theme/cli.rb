# frozen_string_literal: true
module DiscourseTheme
  class Cli
    SETTINGS_FILE = File.expand_path("~/.discourse_theme")

    def usage
      puts "Usage: discourse_theme COMMAND [--reset]"
      puts
      puts "discourse_theme new DIR - Creates a new theme in the designated directory"
      puts "discourse_theme download DIR - Downloads a theme from the server and stores in the designated directory"
      puts "discourse_theme upload DIR - Uploads the theme directory to Discourse"
      puts "discourse_theme watch DIR - Watches the theme directory and synchronizes with Discourse"
      puts
      puts "Use --reset to change the configuration for a directory"
      exit 1
    end

    def run(args)
      usage unless args[1]

      reset = !!args.delete("--reset")

      command = args[0].to_s.downcase
      dir = File.expand_path(args[1])

      config = DiscourseTheme::Config.new(SETTINGS_FILE)
      settings = config[dir]

      theme_id = settings.theme_id
      components = settings.components

      if command == "new"
        raise DiscourseTheme::ThemeError.new "'#{dir}' is not empty" if Dir.exist?(dir) && !Dir.empty?(dir)
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

        choice = UI.select('How would you like to sync this theme?', options.keys)

        if options[choice] == :create
          theme_id = nil
        elsif options[choice] == :select
          themes = render_theme_list(theme_list)
          choice = UI.select('Which theme would you like to sync with?', themes)
          theme_id = extract_theme_id(choice)
          theme = theme_list.find { |t| t["id"] == theme_id }
        end

        about_json = JSON.parse(File.read(File.join(dir, 'about.json'))) rescue nil
        already_uploaded = !!theme
        is_component = theme&.[]("component")
        component_count = about_json&.[]("components")&.length || 0

        if !already_uploaded && !is_component && component_count > 0
          options = {}
          options["Yes"] = :sync
          options["No"] = :none
          options = options.sort_by { |_, b| b == components.to_sym ? 0 : 1 }.to_h if components
          choice = UI.select('Would you like to update child theme components?', options.keys)
          settings.components = components = options[choice].to_s
        end

        uploader = DiscourseTheme::Uploader.new(dir: dir, client: client, theme_id: theme_id, components: components)

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

        choice = UI.select('Which theme would you like to download?', themes)
        theme_id = extract_theme_id(choice)

        UI.progress "Downloading theme into #{dir}"

        downloader.download_theme(theme_id)
        settings.theme_id = theme_id

        UI.success "Theme downloaded"

        watch_theme?(args)
      elsif command == "upload"
        raise DiscourseTheme::ThemeError.new "'#{dir} does not exist" unless Dir.exist?(dir)
        raise DiscourseTheme::ThemeError.new "No theme_id is set, please sync via the 'watch' command initially" if theme_id == 0
        client = DiscourseTheme::Client.new(dir, settings, reset: reset)

        theme_list = client.get_themes_list

        theme = theme_list.find { |t| t["id"] == theme_id }
        raise DiscourseTheme::ThemeError.new "theme_id is set, but the theme does not exist in Discourse" unless theme

        uploader = DiscourseTheme::Uploader.new(dir: dir, client: client, theme_id: theme_id, components: components)

        UI.progress "Uploading theme (id:#{theme_id}) from #{dir} "
        settings.theme_id = theme_id = uploader.upload_full_theme

        UI.success "Theme uploaded (id:#{theme_id})"
        UI.info "Preview: #{client.root}/?preview_theme_id=#{theme_id}"
        if client.is_theme_creator
          UI.info "Manage: #{client.root}/my/themes"
        else
          UI.info "Manage: #{client.root}/admin/customize/themes/#{theme_id}"
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

    def command?(cmd)
      exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
      ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
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
        UI.progress "Running discourse_theme #{args.join(' ')}"
        run(args)
      end
    end

    def render_theme_list(themes)
      themes.sort_by { |t| t["updated_at"] }
        .reverse.map { |theme| "#{theme["name"]} (id:#{theme["id"]})" }
    end

    def extract_theme_id(rendered_name)
      /\(id:([0-9]+)\)$/.match(rendered_name)[1].to_i
    end
  end
end
