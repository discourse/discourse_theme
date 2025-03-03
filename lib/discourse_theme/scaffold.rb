# frozen_string_literal: true

require "date"
require "json"
require "yaml"
require "resolv"

module DiscourseTheme
  class Scaffold
    def self.generate(dir, name:)
      UI.progress "Generating a scaffold theme at #{dir}"

      name = UI.ask("What would you like to call your theme?", default: name).to_s.strip
      is_component = UI.yes?("Is this a component?")

      get_theme_skeleton(dir)

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
        readme.sub!("**Theme Name**", name)
        File.write("README.md", readme)

        encoded_name = name.downcase.gsub(/[^a-zA-Z0-9_-]+/, "-")

        todo_initializer = "javascripts/discourse/api-initializers/todo.js"
        if File.exist?(todo_initializer)
          FileUtils.mv(
            "javascripts/discourse/api-initializers/todo.js",
            "javascripts/discourse/api-initializers/#{encoded_name}.gjs",
          )
        end

        i18n = YAML.safe_load(File.read("locales/en.yml"))
        i18n["en"]["theme_metadata"]["description"] = description
        File.write("locales/en.yml", YAML.safe_dump(i18n).sub(/\A---\n/, ""))

        UI.info "Initializing git repo"
        FileUtils.rm_rf(".git")
        FileUtils.rm_rf("**/.gitkeep")
        system "git", "init", exception: true
        system "git", "symbolic-ref", "HEAD", "refs/heads/main", exception: true
        root_files = Dir.glob("*").select { |f| File.file?(f) }
        system "git", "add", *root_files, exception: true
        system "git", "add", ".*", exception: true
        system "git", "add", "locales", exception: true
        system "git",
               "commit",
               "-m",
               "Initial commit by `discourse_theme` CLI",
               "--quiet",
               exception: true

        if Cli.command?("pnpm")
          UI.info "Installing dependencies"
          system "pnpm", "install", exception: true
        else
          UI.warn "`pnpm` is not installed, skipping installation of linting dependencies"
        end
      end

      puts "✅ Done!"
      puts "See https://meta.discourse.org/t/93648 for more information!"
    end

    private

    def self.get_theme_skeleton(dir)
      if online?
        puts "Downloading discourse-theme-skeleton"
        tmp = Dir.mktmpdir
        system "git",
               "clone",
               "https://github.com/discourse/discourse-theme-skeleton",
               tmp,
               "--depth",
               "1",
               "--quiet",
               exception: true
        FileUtils.rm_rf(skeleton_dir)
        # Store the local copy for offline use
        FileUtils.cp_r(tmp, skeleton_dir)

        FileUtils.cp_r(skeleton_dir, dir)
      elsif Dir.exist?(skeleton_dir)
        puts "⚠️ No internet connection detected, using the local copy of discourse-theme-skeleton"
        FileUtils.cp_r(skeleton_dir, dir)
      else
        raise "🛑 Couldn't download discourse-theme-skeleton"
      end
    end

    def self.online?
      !!Resolv::DNS.new.getaddress("github.com")
    rescue Resolv::ResolvError => e
      false
    end

    def self.skeleton_dir
      File.expand_path("~/.discourse_theme_skeleton")
    end
  end
end
