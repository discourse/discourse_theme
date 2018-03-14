class DiscourseTheme::Watcher
  def initialize(dir, uploader)
    @dir = dir
    @uploader = uploader
  end

  def watch
    listener = Listen.to(@dir) do |modified, added, removed|
      if modified.length == 1 &&
          added.length == 0 &&
          removed.length == 0 &&
          (resolved = resolve_file(modified[0]))

        target, name, type_id = resolved
        print "Updating #{target} #{name}: "

        @uploader.upload_theme_field(
          target: target,
          name: name,
          value: File.read(modified[0]),
          type_id: type_id
        )
      else
        print "Full re-sync is required, re-uploading theme: "
        @uploader.upload_full_theme
      end
    end

    listener.start

  end

  protected

  def resolve_file(path)
    dir_len = File.expand_path(@dir).length
    name = File.expand_path(path)[dir_len + 1..-1]

    target, file = name.split("/")

    if ["common", "desktop", "mobile"].include?(target)
      if file = "#{target}.scss"
        # a CSS file
        return [target, "scss", 1]
      end
    end

    nil
  end


end
