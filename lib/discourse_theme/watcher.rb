module DiscourseTheme
  class Watcher
    def initialize(dir:, uploader:)
      @dir = dir
      @uploader = uploader
    end

    def watch
      listener = Listen.to(@dir) do |modified, added, removed|
        begin
          if modified.length == 1 &&
              added.length == 0 &&
              removed.length == 0 &&
              (resolved = resolve_file(modified[0]))

            target, name, type_id = resolved
            Cli.progress "Fast updating #{target}.scss"

            @uploader.upload_theme_field(
              target: target,
              name: name,
              value: File.read(modified[0]),
              type_id: type_id
            )
          else
            count = modified.length + added.length + removed.length
            if count > 1
              Cli.progress "Detected changes in #{count} files, uploading theme"
            else
              Cli.progress "Detected changes in #{modified[0].gsub(@dir, '')}, uploading theme"
            end
            @uploader.upload_full_theme
          end
          Cli.success "Done! Watching for changes..."
        rescue DiscourseTheme::ThemeError => e
          Cli.error "#{e.message}"
          Cli.progress "Watching for changes..."
        end
      end

      listener.start
      sleep
    end

    protected

    def resolve_file(path)
      dir_len = File.expand_path(@dir).length
      name = File.expand_path(path)[dir_len + 1..-1]

      target, file = name.split("/")

      if ["common", "desktop", "mobile"].include?(target)
        if file == "#{target}.scss"
          # a CSS file
          return [target, "scss", 1]
        end
      end

      nil
    end
  end
end
