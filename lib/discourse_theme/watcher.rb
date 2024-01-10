# frozen_string_literal: true
module DiscourseTheme
  class Watcher
    LISTEN_IGNORE_PATTERNS = [%r{migrations/.+/.+\.js}]

    def self.return_immediately!
      @return_immediately = true
    end

    def self.return_immediately=(val)
      @return_immediately = val
    end

    def self.return_immediately?
      !!@return_immediately
    end

    def self.subscribe_start(&block)
      @subscribers ||= []
      @subscribers << block
    end

    def self.call_start_subscribers
      @subscribers&.each(&:call)
    end

    def self.reset_start_subscribers
      @subscribers = []
    end

    def initialize(dir:, uploader:)
      @dir = dir
      @uploader = uploader
    end

    def watch
      listener =
        Listen.to(@dir, ignore: LISTEN_IGNORE_PATTERNS) do |modified, added, removed|
          yield(modified, added, removed) if block_given?

          begin
            if modified.length == 1 && added.length == 0 && removed.length == 0 &&
                 (resolved = resolve_file(modified[0]))
              target, name, type_id = resolved
              UI.progress "Fast updating #{target}.scss"

              @uploader.upload_theme_field(
                target: target,
                name: name,
                value: File.read(modified[0]),
                type_id: type_id,
              )
            else
              count = modified.length + added.length + removed.length

              if count > 1
                UI.progress "Detected changes in #{count} files, uploading theme"
              else
                filename = modified[0] || added[0] || removed[0]
                UI.progress "Detected changes in #{filename.gsub(@dir, "")}, uploading theme"
              end

              @uploader.upload_full_theme
            end
            UI.success "Done! Watching for changes..."
          rescue DiscourseTheme::ThemeError => e
            UI.error "#{e.message}"
            UI.progress "Watching for changes..."
          end
        end

      listener.start
      self.class.call_start_subscribers
      sleep 1 while !self.class.return_immediately?
    end

    protected

    def resolve_file(path)
      dir_len = File.expand_path(@dir).length
      name = File.expand_path(path)[dir_len + 1..-1]

      target, file = name.split("/")

      if %w[common desktop mobile].include?(target)
        if file == "#{target}.scss"
          # a CSS file
          return target, "scss", 1
        end
      end

      nil
    end
  end
end
