class DiscourseTheme::Downloader

  def initialize(dir:, client:)
    @dir = dir
    @client = client
    @theme_id = nil
  end

  def download_theme(id)
    raw = @client.get_raw_theme_export(id)
    sio = StringIO.new(raw)
    gz = Zlib::GzipReader.new(sio)
    Minitar.unpack(gz, @dir)

    # Minitar extracts into a sub directory, move all the files up one dir
    Dir.chdir(@dir) do
      folders = Dir.glob('*/')
      raise "Extraction failed" unless folders.length == 1
      FileUtils.mv(Dir.glob("#{folders[0]}*"), "./")
      FileUtils.remove_dir(folders[0])
    end
  end

  private

  def add_headers(request)
    if @is_theme_creator
      request["User-Api-Key"] = @api_key
    end
  end
end
