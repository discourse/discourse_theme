module DiscourseTheme
  class Client
    THEME_CREATOR_REGEX = /^https:\/\/theme-creator.discourse.org$/i

    def initialize(dir, settings)
      @url = guess_url(settings)
      @api_key = guess_api_key(settings)

      raise "Missing site to synchronize with!" if !@url
      raise "Missing api key!" if !@api_key

      @is_theme_creator = !!(THEME_CREATOR_REGEX =~ @url)

      parts = discourse_version.split(".").map { |s| s.sub('beta', '').to_i }
      if parts[0] < 2 || parts[1] < 2 || parts[2] < 0 || (!parts[3].nil? && parts[3] < 10)
        Cli.info "discourse_theme is designed for Discourse 2.2.0.beta10 or above"
        Cli.info "download will not function, and syncing destination will be unpredictable"
      end
    end

    def get_themes_list
      endpoint = root +
        if @is_theme_creator
          "/user_themes.json"
        else
          "/admin/customize/themes.json?api_key=#{@api_key}"
        end

      response = request(Net::HTTP::Get.new(endpoint), never_404: true)
      JSON.parse(response.body)["themes"]
    end

    def get_raw_theme_export(id)
      endpoint = root +
        if @is_theme_creator
          "/user_themes/#{id}/export"
        else
          "/admin/customize/themes/#{id}/export?api_key=#{@api_key}"
        end

      response = request(Net::HTTP::Get.new endpoint)
      raise "Error downloading theme: #{response.code}" unless response.code.to_i == 200
      response.body
    end

    def update_theme(id, args)
      endpoint = root +
        if @is_theme_creator
          "/user_themes/#{id}"
        else
          "/admin/themes/#{id}?api_key=#{@api_key}"
        end

      put = Net::HTTP::Put.new(endpoint, 'Content-Type' => 'application/json')
      put.body = args.to_json
      request(put)
    end

    def upload_full_theme(tgz, theme_id:)
      endpoint = root +
        if @is_theme_creator
          "/user_themes/import.json"
        else
          "/admin/themes/import.json?api_key=#{@api_key}"
        end

      post = Net::HTTP::Post::Multipart.new(
        endpoint,
        "theme_id" => theme_id,
        "bundle" => UploadIO.new(tgz, "application/tar+gzip", "bundle.tar.gz")
      )
      request(post)
    end

    def discourse_version
      endpoint = root +
        if @is_theme_creator
          "/about.json"
        else
          "/about.json?api_key=#{@api_key}"
        end

      response = request(Net::HTTP::Get.new(endpoint), never_404: true)
      json = JSON.parse(response.body)
      json["about"]["version"]
    end

    private

    def root
      @url
    end

    def request(request, never_404: false)
      uri = URI.parse(@url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = URI::HTTPS === uri
      add_headers(request)
      http.request(request).tap do |response|
        if response.code == '404' && never_404
          raise DiscourseTheme::ThemeError.new "Error: Incorrect site URL, or API key does not have the correct privileges"
        elsif !['200', '201'].include?(response.code)
          errors = JSON.parse(response.body)["errors"].join(', ') rescue nil
          raise DiscourseTheme::ThemeError.new "Error #{response.code} for #{request.path.split("?")[0]}#{(": " + errors) if errors}"
        end
      end
    rescue Errno::ECONNREFUSED
      raise DiscourseTheme::ThemeError.new "Connection refused for #{request.path}"
    end

    def add_headers(request)
      if @is_theme_creator
        request["User-Api-Key"] = @api_key
      end
    end

    def guess_url(settings)
      url = ENV['DISCOURSE_URL']
      if url
        Cli.progress "Using #{url} from DISCOURSE_URL"
      end

      if !url && settings.url
        url = settings.url
        Cli.progress "Using #{url} from #{DiscourseTheme::Cli::SETTINGS_FILE}"
      end

      if !url
        url = Cli.ask("No site registered for this directory! What is the root URL of your Discourse site?").strip
        url = "http://#{url}" unless url =~ /^https?:\/\//

        # maybe this is an HTTPS redirect
        uri = URI.parse(url)
        if URI::HTTP === uri && uri.port == 80 && is_https_redirect?(url)
          Cli.info "Detected that #{url} should be accessed over https"
          url = url.sub("http", "https")
        end

        if Cli.yes?("Would you like this site name stored in #{DiscourseTheme::Cli::SETTINGS_FILE}?")
          settings.url = url
        end
      end

      url
    end

    def guess_api_key(settings)
      api_key = ENV['DISCOURSE_API_KEY']
      if api_key
        Cli.progress "Using api key from DISCOURSE_API_KEY"
      end

      if !api_key && settings.api_key
        api_key = settings.api_key
        Cli.progress "Using api key from #{DiscourseTheme::Cli::SETTINGS_FILE}"
      end

      if !api_key
        api_key = Cli.ask("No API key found for this directory! What is your API key?").strip
        if Cli.yes?("Would you like this API key stored in #{DiscourseTheme::Cli::SETTINGS_FILE}?")
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

  end
end
