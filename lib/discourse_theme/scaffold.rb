# frozen_string_literal: true

require "date"
require "json"
require "yaml"
require "resolv"

def online?
  !!Resolv::DNS.new.getaddress("github.com")
rescue Resolv::ResolvError => e
  false
end

module DiscourseTheme
  class Scaffold
    SKELETON_DIR = File.expand_path("~/.discourse_theme_skeleton")

    def self.generate(dir, name:)
      UI.progress "Generating a scaffold theme at #{dir}"

      name = UI.ask("What would you like to call your theme?", default: name).to_s.strip
      is_component = UI.yes?("Is this a component?")

      if online?
        puts "Downloading discourse-plugin-skeleton"
        tmp = Dir.mktmpdir
        system "git",
               "clone",
               "https://github.com/discourse/discourse-theme-skeleton",
               tmp,
               "--depth",
               "1",
               exception: true
        FileUtils.rm_rf(SKELETON_DIR)
        # Store the local copy for offline use
        FileUtils.cp_r(tmp, SKELETON_DIR)

        FileUtils.cp_r(SKELETON_DIR, dir)
      elsif Dir.exist?(SKELETON_DIR)
        puts "⚠️ No internet connection detected, using the local copy of discourse-plugin-skeleton"
        FileUtils.cp_r(SKELETON_DIR, dir)
      else
        raise "🛑 Couldn't download discourse-plugin-skeleton"
      end

      Dir.chdir dir do
        author = UI.ask("Who is authoring the theme?", default: "Discourse").to_s.strip
        description = UI.ask("How would you describe this theme?").to_s.strip

        about = JSON.parse(File.read("about.json"))
        about["name"] = name
        about["authors"] = author
        if !is_component
          about.delete("component")
          about["color_schemes"] = {}
        end
        File.write("about.json", JSON.pretty_generate(about))

        if author != "Discourse"
          license = File.read("LICENSE")
          license.sub!(/^(Copyright\s\(c\))\s(.+)/, "\\1 #{author}")
          File.write("LICENSE", license)
        end

        readme = File.read("README.md")
        readme.sub!("**Theme Name**", "**#{name}**")
        File.write("README.md", readme)

        encoded_name = name.downcase.gsub(/[^a-zA-Z0-9_-]+/, "-")
        FileUtils.mv(
          "javascripts/discourse/api-initializers/todo.js",
          "javascripts/discourse/api-initializers/#{encoded_name}.js",
        )

        i18n = YAML.safe_load(File.read("locales/en.yml"))
        i18n["en"]["theme_metadata"]["description"] = description
        File.write("locales/en.yml", YAML.safe_dump(i18n).sub(/\A---\n/, ""))

        UI.info "Initializing git repo"
        FileUtils.rm_rf(".git")
        system "git", "init", exception: true
        system "git", "symbolic-ref", "HEAD", "refs/heads/main", exception: true
        system "git", "add", "-A", exception: true
        system "git", "commit", "-m", "Initial commit"

        UI.info "Installing dependencies"
        system "yarn", exception: true
      end

      puts "✅ Done!"
      puts "See https://meta.discourse.org/t/how-to-develop-custom-themes/60848 for more information!"
    end
  end
end
