# frozen_string_literal: true

require 'date'
require 'json'

module DiscourseTheme
  class Scaffold

    ABOUT_JSON = {
      about_url: nil,
      license_url: nil,
      assets: {}
    }

    HELP = <<~STR
      Are you a bit lost? Be sure to read https://meta.discourse.org/t/how-to-develop-custom-themes/60848
    STR

    LICENSE = <<~STR
      Copyright #YEAR #AUTHOR

      Permission is hereby granted, free of charge, to any person obtaining a copy
      of this software and associated documentation files (the "Software"), to deal
      in the Software without restriction, including without limitation the rights
      to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
      copies of the Software, and to permit persons to whom the Software is
      furnished to do so, subject to the following conditions:

      The above copyright notice and this permission notice shall be included in all
      copies or substantial portions of the Software.

      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
      IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
      AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
      LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
      OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
      SOFTWARE.
    STR

    GIT_IGNORE = <<~STR
      .discourse-site
      node_modules
      HELP
    STR

    API_INITIALIZER = <<~STR
      import { apiInitializer } from "discourse/lib/api";

      export default apiInitializer("1.8.0", api => {
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
        "extends": "eslint-config-discourse",
        "globals": {
          "settings": "readonly",
          "themePrefix": "readonly"
        }
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

    SETTINGS_YML = <<~YAML
      foo_setting:
        default: ""
    YAML

    def self.generate(dir)
      UI.progress "Generating a scaffold theme at #{dir}"

      name = loop do
        input = UI.ask("What would you like to call your theme?").to_s.strip
        if input.empty?
          UI.error("Theme name cannot be empty")
        else
          break input
        end
      end

      is_component = UI.yes?("Is this a component?")

      FileUtils.mkdir_p dir
      Dir.chdir dir do
        author = loop do
          input = UI.ask("Who is authoring the theme?", default: ENV['USER']).to_s.strip
          if input.empty?
            UI.error("Author cannot be empty")
          else
            break input
          end
        end

        description = UI.ask("How would you describe this theme?").to_s.strip

        about_template = ABOUT_JSON.dup
        about_template[:name] = name
        if is_component
          about_template[:component] = true
        else
          about_template[:color_schemes] = {}
        end

        encoded_name = name.downcase.gsub(/[^a-zA-Z0-9_-]+/, '_')

        write('about.json', JSON.pretty_generate(about_template))
        write('HELP', HELP)
        write('LICENSE', LICENSE.sub("#YEAR", "#{Date.today.year}").sub("#AUTHOR", author))
        write('.eslintrc', ESLINT_RC)
        write('.gitignore', GIT_IGNORE)
        write('.template-lintrc.js', TEMPLATE_LINT_RC)
        write('package.json', PACKAGE_JSON.sub("#AUTHOR", author))
        write('settings.yml', SETTINGS_YML)
        write('common/common.scss', '')
        write("javascripts/discourse/api-initializers/#{encoded_name}.js", API_INITIALIZER)
        write('locales/en.yml', EN_YML.sub("#DESCRIPTION", description))

        UI.info "Initializing git repo"
        puts `git init && git symbolic-ref HEAD refs/heads/main`

        UI.info "Installing dependencies"
        puts `yarn`
      end
    end

    private

    def self.write(filename, contents)
      UI.info "Creating #{filename}"
      FileUtils.mkdir_p(File.dirname(filename))
      File.write(filename, contents)
    end
  end
end
