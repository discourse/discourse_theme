module DiscourseTheme
  class Cli

    @@prompt = ::TTY::Prompt.new(help_color: :cyan)
    @@pastel = Pastel.new

    def self.yes?(message)
      @@prompt.yes?(@@pastel.cyan("? ") + message)
    end

    def self.ask(message, default: nil)
      @@prompt.ask(@@pastel.cyan("? ") + message, default: default)
    end

    def self.select(message, options)
      @@prompt.select(@@pastel.cyan("? ") + message, options)
    end

    def self.info(message)
      puts @@pastel.blue("i ") + message
    end

    def self.progress(message)
      puts @@pastel.yellow("» ") + message
    end

    def self.error(message)
      puts @@pastel.red("✘ #{message}")
    end

    def self.success(message)
      puts @@pastel.green("✔ #{message}")
    end

    SETTINGS_FILE = File.expand_path("~/.discourse_theme")

    def usage
      puts "Usage: discourse_theme COMMAND [--reset]"
      puts
      puts "discourse_theme new DIR : Creates a new theme in the designated directory"
      puts "discourse_theme download DIR : Download a theme from the server, and store in the designated directory"
      puts "discourse_theme watch DIR : Watches the theme directory and synchronizes with Discourse"
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
        raise DiscourseTheme::ThemeError.new "'#{dir} is not empty" if Dir.exists?(dir) && !Dir.empty?(dir)
        DiscourseTheme::Scaffold.generate(dir)
        if Cli.yes?("Would you like to start 'watching' this theme?")
          args[0] = "watch"
          Cli.progress "Running discourse_theme #{args.join(' ')}"
          run(args)
        end
      elsif command == "watch"
        raise DiscourseTheme::ThemeError.new "'#{dir} does not exist" unless Dir.exists?(dir)
        client = DiscourseTheme::Client.new(dir, settings, reset: reset)

        theme_list = client.get_themes_list

        options = {}
        if theme_id && theme = theme_list.find { |t| t["id"] == theme_id }
          options["Sync with existing theme: '#{theme["name"]}' (id:#{theme_id})"] = :default
        end
        options["Create and sync with a new theme"] = :create
        options["Select a different theme"] = :select

        choice = Cli.select('How would you like to sync this theme?', options.keys)

        if options[choice] == :create
          theme_id = nil
        elsif options[choice] == :select
          themes = render_theme_list(theme_list)
          choice = Cli.select('Which theme would you like to sync with?', themes)
          theme_id = extract_theme_id(choice)
          theme = theme_list.find { |t| t["id"] == theme_id }
        end

        if !theme || theme["component"] == false
          options = {}
          options["Yes"] = :sync
          options["No"] = :none
          options = options.sort_by { |_, b| b == components.to_sym ? 0 : 1 }.to_h if components
          choice = Cli.select('Would you like to update child theme components?', options.keys)
          settings.components = components = options[choice].to_s
        end

        uploader = DiscourseTheme::Uploader.new(dir: dir, client: client, theme_id: theme_id, components: components)

        Cli.progress "Uploading theme from #{dir}"
        settings.theme_id = theme_id = uploader.upload_full_theme

        Cli.success "Theme uploaded (id:#{theme_id})"
        watcher = DiscourseTheme::Watcher.new(dir: dir, uploader: uploader)

        Cli.progress "Watching for changes in #{dir}..."
        watcher.watch

      elsif command == "download"
        client = DiscourseTheme::Client.new(dir, settings, reset: reset)
        downloader = DiscourseTheme::Downloader.new(dir: dir, client: client)

        FileUtils.mkdir_p dir unless Dir.exists?(dir)
        raise DiscourseTheme::ThemeError.new "'#{dir} is not empty" unless Dir.empty?(dir)

        Cli.progress "Loading theme list..."
        themes = render_theme_list(client.get_themes_list)

        choice = Cli.select('Which theme would you like to download?', themes)
        theme_id = extract_theme_id(choice)

        Cli.progress "Downloading theme into #{dir}"

        downloader.download_theme(theme_id)
        settings.theme_id = theme_id

        Cli.success "Theme downloaded"

        if Cli.yes?("Would you like to start 'watching' this theme?")
          args[0] = "watch"
          Cli.progress "Running discourse_theme #{args.join(' ')}"
          run(args)
        end
      else
        usage
      end

      Cli.progress "Exiting..."
    rescue DiscourseTheme::ThemeError => e
      Cli.error "#{e.message}"
    rescue Interrupt, TTY::Reader::InputInterrupt => e
      Cli.error "Interrupted"
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
