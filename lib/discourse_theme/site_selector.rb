# frozen_string_literal: true
module DiscourseTheme
  class SiteSelector
    def self.select_site(settings, dir)
      if settings.has_multiple_sites?
        sites = settings.site_names
        options = {}
        
        sites.each do |site_name|
          site_config = settings.site_config(site_name)
          options["#{site_name} (#{site_config['url']})"] = site_name
        end
        
        options["Configure a new site"] = :new_site
        
        choice = UI.select("Which site would you like to watch?", options.keys)
        selected = options[choice]
        
        if selected == :new_site
          return configure_new_site(settings, dir)
        else
          return selected
        end
      else
        if settings.url
          return nil
        else
          return configure_new_site(settings, dir)
        end
      end
    end
    
    def self.configure_new_site(settings, dir)
      UI.info "Configuring a new site..."
      
      site_name = UI.ask("Enter a name for this site (e.g., 'localhost', 'staging', 'production'):")
      return nil if site_name.nil? || site_name.strip.empty?
      
      site_name = site_name.strip
      
      if settings.site_names.include?(site_name)
        UI.error "A site with name '#{site_name}' already exists!"
        return nil
      end
      
      url = UI.ask("Enter the site URL:")
      return nil if url.nil? || url.strip.empty?
      
      url = url.strip
      temp_client = DiscourseTheme::Client.new(dir, settings, reset: false, url: url)
      theme_list = temp_client.get_themes_list
      
      options = {}
      options["Create and sync with a new theme"] = :create
      
      if theme_list && !theme_list.empty?
        options["Select an existing theme"] = :select
      end
      
      choice = UI.select("How would you like to sync this theme?", options.keys)
      
      theme_id = nil
      if options[choice] == :select
        themes = render_theme_list(theme_list)
        theme_choice = UI.select("Which theme would you like to sync with?", themes)
        theme_id = extract_theme_id(theme_choice)
      end
      
      settings.add_site(site_name, url: url, theme_id: theme_id)
      
      UI.success "Site '#{site_name}' configured successfully!"
      return site_name
    end
    
    private
    
    def self.render_theme_list(themes)
      themes.map do |theme|
        "#{theme["name"]} (id: #{theme["id"]})"
      end
    end
    
    def self.extract_theme_id(choice)
      choice.match(/\(id: (\d+)\)/)[1].to_i if choice
    end
  end
end
