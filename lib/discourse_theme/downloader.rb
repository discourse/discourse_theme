# frozen_string_literal: true
require "zip"

class DiscourseTheme::Downloader
  def initialize(dir:, client:)
    @dir = dir
    @client = client
    @theme_id = nil
  end

  def download_theme(id)
    raw, filename = @client.get_raw_theme_export(id)

    if filename.end_with?(".zip")
      Zip::File.open_buffer(raw) do |zip_file|
        zip_file.each do |entry|
          new_path = File.join(@dir, entry.name)
          entry.extract(new_path)
        end
      end
    else
      sio = StringIO.new(raw)
      gz = Zlib::GzipReader.new(sio)
      Minitar.unpack(gz, @dir)

      # Minitar extracts into a sub directory, move all the files up one dir
      Dir.chdir(@dir) do
        folders = Dir.glob("*/")
        raise "Extraction failed" unless folders.length == 1
        FileUtils.mv(Dir.glob("#{folders[0]}*"), "./")
        FileUtils.remove_dir(folders[0])
      end
    end
  end

  private

  def add_headers(request)
    request["User-Api-Key"] = @api_key if @is_theme_creator
  end
end
