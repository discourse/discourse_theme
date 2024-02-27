# frozen_string_literal: true

require "date"
require "json"
require "yaml"

module DiscourseTheme
  class Scaffold
    SKELETON_DIR = File.expand_path("~/.discourse_theme_skeleton")

    def self.generate(dir)
      UI.progress "Generating a scaffold theme at #{dir}"

      name =
        loop do
          input = UI.ask("What would you like to call your theme?").to_s.strip
          if input.empty?
            UI.error("Theme name cannot be empty")
          else
            break input
          end
        end

      is_component = UI.yes?("Is this a component?")

      if Dir.exist?(SKELETON_DIR)
        puts `cd #{SKELETON_DIR} && git pull`
      else
        FileUtils.mkdir_p(SKELETON_DIR)
        puts `git clone https://github.com/discourse/discourse-theme-skeleton #{SKELETON_DIR}`
      end

      FileUtils.cp_r(SKELETON_DIR, dir)

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

        UI.info "Installing dependencies"
        puts `yarn`
      end

      puts "✅ Done!"
      puts "See https://meta.discourse.org/t/how-to-develop-custom-themes/60848 for more information!"
    end
  end
end
