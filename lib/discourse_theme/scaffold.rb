# frozen_string_literal: true

require 'json'

module DiscourseTheme
  class Scaffold

    BLANK_FILES = %w{
      common/common.scss

      settings.yml
    }

    ABOUT_JSON = {
      about_url: nil,
      license_url: nil,
      assets: {}
    }

    HELP = <<~STR
      Are you a bit lost? Be sure to read https://meta.discourse.org/t/how-to-develop-custom-themes/60848
    STR

    GIT_IGNORE = <<~STR
      .discourse-site
      node_modules
      HELP
    STR

    API_INITIALIZER = <<~STR
      import { apiInitializer } from "discourse/lib/api";

      export default apiInitializer("0.11.1", api => {
        console.log("hello world from api initializer!");
      });
    STR

    PACKAGE_JSON = <<~STR
      {
        "author": "#AUTHOR",
        "license": "MIT",
        "devDependencies": {
          "eslint-config-discourse": "latest"
        }
      }
    STR

    ESLINT_RC = <<~STR
      {
        "extends": "eslint-config-discourse"
      }
    STR

    TEMPLATE_LINT_RC = <<~STR
      module.exports = {
        plugins: ["ember-template-lint-plugin-discourse"],
        extends: "discourse:recommended",
      };
    STR

    EN_YML = <<~YAML
      en:
        theme_metadata:
          description: "#DESCRIPTION"
    YAML

    def self.generate(dir)
      UI.progress "Generating a scaffold theme at #{dir}"

      name = UI.ask("What would you like to call your theme?").strip
      is_component = UI.yes?("Is this a component?")

      FileUtils.mkdir_p dir
      Dir.chdir dir do
        UI.info "Creating about.json"
        about_template = ABOUT_JSON.dup
        about_template[:name] = name
        if is_component
          about_template[:component] = true
        else
          about_template[:color_schemes] = {}
        end
        File.write('about.json', JSON.pretty_generate(about_template))

        UI.info "Creating HELP"
        File.write('HELP', HELP)

        UI.info "Creating package.json"
        author = UI.ask("Who is authoring the theme?").strip
        File.write('package.json', PACKAGE_JSON.sub("#AUTHOR", author))

        UI.info "Creating .template-lintrc.js"
        File.write('.template-lintrc.js', TEMPLATE_LINT_RC)

        UI.info "Creating .eslintrc"
        File.write('.eslintrc', ESLINT_RC)

        UI.info "Creating .gitignore"
        File.write('.gitignore', GIT_IGNORE)

        locale = "locales/en.yml"
        UI.info "Creating #{locale}"
        FileUtils.mkdir_p(File.dirname(locale))
        description = UI.ask("How would you describe this theme?").strip
        File.write(locale, EN_YML.sub("#DESCRIPTION", description))

        initializer = "javascripts/discourse/api-initializers/#{name}.js"
        UI.info "Creating #{initializer}"
        FileUtils.mkdir_p(File.dirname(initializer))
        File.write(initializer, API_INITIALIZER)

        BLANK_FILES.each do |f|
          UI.info "Creating #{f}"
          FileUtils.mkdir_p File.dirname(f)
          FileUtils.touch f
        end

        UI.info "Initializing git repo"
        puts `git init .`

        UI.info "Installing dependencies"
        puts `yarn`
      end
    end
  end
end
