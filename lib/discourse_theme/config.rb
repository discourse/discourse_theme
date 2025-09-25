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

    def possible_url
      return safe_config["url"] if safe_config["url"]

      first_config = @config.raw_config.values.find { |config| config["url"] }
      first_config["url"] if first_config
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

    def local_discourse_directory_configured?
      !safe_config["local_discourse_directory"].nil?
    end

    def local_discourse_directory
      safe_config["local_discourse_directory"]
    end

    def local_discourse_directory=(dir)
      set("local_discourse_directory", dir)
    end

    def sites
      safe_config["sites"] || {}
    end

    def add_site(name, url:, theme_id:, components: nil)
      sites_config = sites
      sites_config[name] = {
        "url" => url,
        "theme_id" => theme_id
      }
      sites_config[name]["components"] = components if components
      set("sites", sites_config)
    end

    def remove_site(name)
      sites_config = sites
      sites_config.delete(name)
      set("sites", sites_config)
    end

    def site_names
      sites.keys
    end

    def site_config(name)
      sites[name] || {}
    end

    def has_multiple_sites?
      sites.any?
    end

    def effective_url(site_name = nil)
      if site_name && sites[site_name]
        sites[site_name]["url"]
      elsif has_multiple_sites? && site_name.nil?
        nil
      else
        url
      end
    end

    def effective_theme_id(site_name = nil)
      if site_name && sites[site_name]
        sites[site_name]["theme_id"].to_i
      elsif has_multiple_sites? && site_name.nil?
        nil
      else
        theme_id
      end
    end

    def effective_components(site_name = nil)
      if site_name && sites[site_name]
        sites[site_name]["components"]
      elsif has_multiple_sites? && site_name.nil?
        nil
      else
        components
      end
    end

    def api_key_for_url(url)
      search_api_key(url)
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
      rescue StandardError
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
