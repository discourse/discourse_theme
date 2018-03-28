class DiscourseTheme::Scaffold

  BLANK_FILES = %w{
    common/common.scss
    common/header.html
    common/after_header.html
    common/footer.html
    common/head_tag.html
    common/body_tag.html
    common/embedded.scss

    desktop/desktop.scss
    desktop/header.html
    desktop/after_header.html
    desktop/footer.html
    desktop/head_tag.html
    desktop/body_tag.html

    mobile/mobile.scss
    mobile/header.html
    mobile/after_header.html
    mobile/footer.html
    mobile/head_tag.html
    mobile/body_tag.html

    settings.yml
  }

  ABOUT_JSON = <<~STR
    {
      "name": "#NAME#",
      "about_url": "URL",
      "license_url": "URL",
      "assets": {
      },
      "color_schemes": {
      }
    }
  STR

  HELP = <<~STR
    Are you a bit lost? Be sure to read https://meta.discourse.org/t/how-to-develop-custom-themes/60848
  STR

  GIT_IGNORE = <<~STR
    .discourse-site
    HELP
  STR

  def self.generate(dir)
    puts "Generating a scaffold theme at #{dir}"

    puts "What would you like to call your theme? "
    name = STDIN.gets.strip
    if name.length == 0
      puts "Please pick a name"
      exit 1
    end

    FileUtils.mkdir_p dir
    Dir.chdir dir do
      File.write('about.json', ABOUT_JSON.sub("#NAME#", name))
      File.write('HELP', HELP)
      File.write('.gitignore', GIT_IGNORE)

      BLANK_FILES.each do |f|
        puts "#{f}"
        FileUtils.mkdir_p File.dirname(f)
        FileUtils.touch f
      end

      puts "Initializing git repo"
      puts `git init .`
    end
  end
end
