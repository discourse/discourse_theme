class DiscourseTheme::Cli

  SETTINGS_FILE = File.expand_path("~/.discourse_theme")

  def usage
    puts "Usage: discourse_theme COMMAND"
    puts
    puts "discourse_theme new DIR : Creates a new theme in the designated directory"
    puts "discourse_theme watch DIR : Watches the theme directory and synchronizes with Discourse"
    exit 1
  end

  def guess_api_key(settings)
    api_key = ENV['DISCOURSE_API_KEY']
    if api_key
      puts "Using api_key provided by DISCOURSE_API_KEY"
    end

    if !api_key && settings.api_key
      api_key = settings.api_key
      puts "Using previously stored api key in #{SETTINGS_FILE}"
    end

    if !api_key
      puts "No API key found in DISCOURSE_API_KEY env var enter your API key: "
      api_key = STDIN.gets.strip
      puts "Would you like me to store this API key in #{SETTINGS_FILE}? (Yes|No)"
      answer = STDIN.gets.strip
      if answer =~ /y(es)?/i
        settings.api_key = api_key
      end
    end

    api_key
  end

  def is_https_redirect?(url)
    url = URI.parse(url)
    path = url.path
    path = "/" if path.empty?
    req = Net::HTTP::Get.new("/")
    response = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
    Net::HTTPRedirection === response && response['location'] =~ /^https/i
  end

  def guess_url(settings)
    url = ENV['DISCOURSE_URL']
    if url
      puts "Site provided by DISCOURSE_URL"
    end

    if !url && settings.url
      url = settings.url
      puts "Using #{url} defined in #{SETTINGS_FILE}"
    end

    if !url
      puts "No site found! Where would you like to synchronize the theme to: "
      url = STDIN.gets.strip
      url = "http://#{url}" unless url =~ /^https?:\/\//

      # maybe this is an HTTPS redirect
      uri = URI.parse(url)
      if URI::HTTP === uri && uri.port == 80 && is_https_redirect?(url)
        puts "Detected an #{url} is an HTTPS domain"
        url = url.sub("http", "https")
      end

      puts "Would you like me to store this site name at: #{SETTINGS_FILE}? (Yes|No)"
      answer = STDIN.gets.strip
      if answer =~ /y(es)?/i
        settings.url = url
      end
    end

    url
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

      config = DiscourseTheme::Config.new(SETTINGS_FILE)
      settings = config[dir]

      url = guess_url(settings)
      api_key = guess_api_key(settings)

      if !url
        puts "Missing site to synchronize with!"
        usage
      end

      if !api_key
        puts "Missing api key!"
        usage
      end

      uploader = DiscourseTheme::Uploader.new(dir: dir, api_key: api_key, site: url)
      print "Uploading theme from #{dir} to #{url} : "
      uploader.upload_full_theme

      watcher = DiscourseTheme::Watcher.new(dir: dir, uploader: uploader)

      watcher.watch
    else
      usage
    end
  end
end
