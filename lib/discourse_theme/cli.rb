class DiscourseTheme::Cli

  WATCHER_SETTINGS_FILE = File.expand_path("~/.discourse-theme-watcher")

  def usage
    puts "Usage: discourse-theme COMMAND"
    puts
    puts "discourse-theme new DIR : Creates a new theme in the designated directory"
    puts "discourse-theme watch DIR : Watches the theme directory and synchronizes with Discourse"
    exit 1
  end

  def guess_api_key
    api_key = ENV['DISCOURSE_API_KEY']
    if api_key
      puts "Using api_key provided by DISCOURSE_API_KEY"
    end

    if !api_key && File.exist?(WATCHER_SETTINGS_FILE)
      api_key = File.read(WATCHER_SETTINGS_FILE).strip
      puts "Using previously stored api key in #{WATCHER_SETTINGS_FILE}"
    end

    if !api_key
      puts "No API key found in DISCOURSE_API_KEY env var enter your API key: "
      api_key = STDIN.gets.strip
      puts "Would you like me to store this API key in #{WATCHER_SETTINGS_FILE}? (Yes|No)"
      answer = STDIN.gets.strip
      if answer =~ /y(es)?/i
        File.write WATCHER_SETTINGS_FILE, api_key
      end
    end

    api_key
  end

  def guess_site(dir)
    site = ENV['DISCOURSE_SITE']
    if site
      puts "Site provided by DISCOURSE_SITE"
    end

    site_conf = dir + "/.discourse-site"

    if !site && File.exist?(site_conf)
      site = File.read(site_conf).strip
      puts "Using #{site} defined in #{site_conf}"
    end

    if !site
      puts "No site found, where would you like to synchronize the theme to: "
      site = STDIN.gets.strip
      puts "Would you like me to store this site name at: #{site_conf}? (Yes|No)"
      answer = STDIN.gets.strip
      if answer =~ /y(es)?/i
        File.write site_conf, site
        # got to make sure this is in .gitignore

        gitignore = File.read(dir + "/.gitignore") rescue ""
        if gitignore !~ /^.discourse-site/
          gitignore.strip!
          gitignore += "\n.discourse-site"
          File.write(dir + '/.gitignore', gitignore)
        end
      end
    end

    site
  end

  def run
    usage unless ARGV[1]

    command = ARGV[0].to_s.downcase
    dir = File.expand_path(ARGV[1])

    dir_exists = File.exist?(dir)

    if command == "new" && !dir_exists
      DiscourseTheme::Scaffold.generate(dir)
    elsif command == "watch" && dir_exists
      if !File.exist?("#{dir}/about.json")
        puts "No about.json file found in #{dir}!"
        puts
        usage
      end

      api_key = guess_api_key
      site = guess_site(dir)

      if !site
        puts "Missing site!"
        usage
      end

      if !api_key
        puts "Missing api key!"
        usage
      end

      uploader = DiscourseTheme::Uploader.new(dir: dir, api_key: api_key, site: site)
      print "Uploading theme from #{dir} to #{site} : "
      uploader.upload_full_theme

      watcher = DiscourseTheme::Watcher.new(dir: dir, uploader: uploader)

      watcher.watch
    else
      usage
    end
  end
end
