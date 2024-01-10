# frozen_string_literal: true
module DiscourseTheme
  class UI
    @@prompt = ::TTY::Prompt.new(help_color: :cyan)
    @@pastel = Pastel.new

    def self.yes?(message)
      @@prompt.yes?(@@pastel.cyan("? ") + message)
    end

    def self.ask(message, default: nil)
      @@prompt.ask(@@pastel.cyan("? ") + message, default: default)
    end

    def self.select(message, options)
      @@prompt.select(@@pastel.cyan("? ") + message, options)
    end

    def self.info(message)
      puts @@pastel.blue("i ") + message
    end

    def self.progress(message)
      puts @@pastel.yellow("» ") + message
    end

    def self.error(message)
      puts @@pastel.red("✘ #{message}")
    end

    def self.warn(message)
      puts @@pastel.yellow("⚠ #{message}")
    end

    def self.success(message)
      puts @@pastel.green("✔ #{message}")
    end
  end
end
