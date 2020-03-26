module DiscourseTheme
  class Uploader

    THEME_CREATOR_REGEX = /^https:\/\/theme-creator.discourse.org$/i

    def initialize(dir:, client:, theme_id: nil, components: nil)
      @dir = dir
      @client = client
      @theme_id = theme_id
      @components = components
    end

    def compress_dir(gzip, dir)
      sgz = Zlib::GzipWriter.new(File.open(gzip, 'wb'))
      tar = Archive::Tar::Minitar::Output.new(sgz)

      Dir.chdir(dir + "/../") do
        Find.find(File.basename(dir)) do |x|
          bn = File.basename(x)
          Find.prune if bn == "node_modules" || bn == "src" || bn[0] == ?.
          next if File.directory?(x)

          Minitar.pack_file(x, tar)
        end
      end
    ensure
      tar.close
      sgz.close
    end

    def diagnose_errors(json)
      count = 0
      json["theme"]["theme_fields"].each do |row|
        if (error = row["error"]) && error.length > 0
          count += 1
          Cli.error ""
          Cli.error "Error in #{row["target"]} #{row["name"]}: #{row["error"]}"
          Cli.error ""
        end
      end
      count
    end

    def upload_theme_field(target: , name: , type_id: , value:)
      raise "expecting theme_id to be set!" unless @theme_id

      args = {
        theme: {
          theme_fields: [{
            name: name,
            target: target,
            type_id: type_id,
            value: value
          }]
        }
      }

      response = @client.update_theme(@theme_id, args)
      json = JSON.parse(response.body)
        if diagnose_errors(json) != 0
          Cli.error "(end of errors)"
        end
    end

    def upload_full_theme
      filename = "#{Pathname.new(Dir.tmpdir).realpath}/bundle_#{SecureRandom.hex}.tar.gz"
      compress_dir(filename, @dir)

      File.open(filename) do |tgz|
        response = @client.upload_full_theme(tgz, theme_id: @theme_id, components: @components)

        json = JSON.parse(response.body)
        @theme_id = json["theme"]["id"]
        if diagnose_errors(json) != 0
          Cli.error "(end of errors)"
        end
        @theme_id
      end
    ensure
      FileUtils.rm_f filename
    end

  end
end
