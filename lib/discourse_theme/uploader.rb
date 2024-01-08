# frozen_string_literal: true
module DiscourseTheme
  class Uploader
    def self.upload_full_theme_callbacks
      @upload_callbacks ||= []
    end

    # Used in the test environment to register a callback that is called with the directory of the theme being uploaded.
    def self.register_upload_full_theme_callback(&block)
      self.upload_full_theme_callbacks << block
    end

    # Used in the test environment to clear the registered callbacks.
    def self.reset_upload_full_theme_callbacks
      self.upload_full_theme_callbacks.clear
    end

    def initialize(dir:, client:, theme_id: nil, components: nil)
      @dir = dir
      @client = client
      @theme_id = theme_id
      @components = components
    end

    def compress_dir(gzip, dir)
      sgz = Zlib::GzipWriter.new(File.open(gzip, "wb"))
      tar = Archive::Tar::Minitar::Output.new(sgz)

      Dir.chdir(dir + "/../") do
        Find.find(File.basename(dir)) do |x|
          bn = File.basename(x)
          Find.prune if bn == "node_modules" || bn == "src" || bn[0] == "."
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
          UI.error ""
          UI.error "Error in #{row["target"]} #{row["name"]}: #{row["error"]}"
          UI.error ""
        end
      end
      count
    end

    def upload_theme_field(target:, name:, type_id:, value:)
      raise "expecting theme_id to be set!" unless @theme_id

      args = {
        theme: {
          theme_fields: [{ name: name, target: target, type_id: type_id, value: value }],
        },
      }

      response = @client.update_theme(@theme_id, args)
      json = JSON.parse(response.body)
      UI.error "(end of errors)" if diagnose_errors(json) != 0
    end

    def upload_full_theme(ignore_files: [])
      filename = "#{Pathname.new(Dir.tmpdir).realpath}/bundle_#{SecureRandom.hex}.tar.gz"
      temp_dir = nil

      theme_dir =
        if !ignore_files.empty?
          temp_dir = Dir.mktmpdir
          FileUtils.copy_entry(@dir, temp_dir)
          dir_pathname = Pathname.new(@dir)
          ignore_files.each { |file| FileUtils.rm_f(File.join(temp_dir, file)) }
          temp_dir
        else
          @dir
        end

      self.class.upload_full_theme_callbacks.each { |cb| cb.call(theme_dir) }

      compress_dir(filename, theme_dir)

      File.open(filename) do |tgz|
        response = @client.upload_full_theme(tgz, theme_id: @theme_id, components: @components)

        json = JSON.parse(response.body)
        @theme_id = json["theme"]["id"]
        UI.error "(end of errors)" if diagnose_errors(json) != 0
        @theme_id
      end
    ensure
      FileUtils.rm_rf(temp_dir) if temp_dir
      FileUtils.rm_f(filename)
    end
  end
end
