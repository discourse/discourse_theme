class DiscourseTheme::Config

  class PathSetting
    def initialize(config, path)
      @config = config
      @path = path
    end

    def api_key
      safe_config["api_key"]
    end

    def api_key=(val)
      set("api_key", val)
    end

    def url
      safe_config["url"]
    end

    def url=(val)
      set("url", val)
    end

    protected

    def set(name, val)
      hash = @config.raw_config[@path] ||= {}
      hash[name] = val
      @config.save
      val
    end

    def safe_config
      config = @config.raw_config[@path]
      if Hash === config
        config
      else
        {}
      end
    end
  end

  attr_reader :raw_config, :filename

  def initialize(filename)
    @filename = filename

    if File.exist?(@filename)
      begin
        @raw_config = YAML.load_file(@filename)
        raise unless Hash === @raw_config
      rescue
        @raw_config = {}
        $stderr.puts "ERROR: #{@filename} contains invalid config, resetting"
      end
    else
      @raw_config = {}
    end
  end

  def set(path, url:, api_key:)
    @raw_config[path] = {
      "url" => url,
      "api_key" => api_key
    }
  end

  def save
    File.write(@filename, @raw_config.to_yaml)
  end

  def [](path)
    PathSetting.new(self, path)
  end
end
