# frozen_string_literal: true
class DiscourseTheme::Config

  class PathSetting
    def initialize(config, path)
      @config = config
      @path = path
    end

    def api_key
      search_api_key(url) || safe_config["api_key"]
    end

    def api_key=(val)
      set_api_key(url, val)
    end

    def url
      safe_config["url"]
    end

    def url=(val)
      set("url", val)
    end

    def theme_id
      safe_config["theme_id"].to_i
    end

    def theme_id=(theme_id)
      set("theme_id", theme_id.to_i)
    end

    def components
      safe_config["components"]
    end

    def components=(val)
      set("components", val)
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

    def search_api_key(url)
      hash = @config.raw_config["api_keys"]
      hash[url] if hash
    end

    def set_api_key(url, api_key)
      hash = @config.raw_config["api_keys"] ||= {}
      hash[url] = api_key
      @config.save
      api_key
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

  def save
    File.write(@filename, @raw_config.to_yaml)
  end

  def [](path)
    PathSetting.new(self, path)
  end
end
