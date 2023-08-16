# frozen_string_literal: true
require "test_helper"
require "base64"

class TestCli < Minitest::Test
  def setup
    WebMock.reset!
    @dir = Dir.mktmpdir

    @root_stub =
      stub_request(:get, "http://my.forum.com").to_return(status: 200, body: "", headers: {})

    @about_stub =
      stub_request(:get, "http://my.forum.com/about.json").to_return(
        status: 200,
        body: { about: { version: "2.2.0" } }.to_json,
      )

    @themes_stub =
      stub_request(:get, "http://my.forum.com/admin/customize/themes.json").to_return(
        status: 200,
        body: {
          themes: [{ id: 1, name: "Magic theme" }, { id: 5, name: "Amazing theme" }],
        }.to_json,
      )

    @import_stub =
      stub_request(:post, "http://my.forum.com/admin/themes/import.json").to_return(
        status: 200,
        body: { theme: { id: "6", name: "Uploaded theme", theme_fields: [] } }.to_json,
      )

    @download_tar_stub =
      stub_request(:get, "http://my.forum.com/admin/customize/themes/5/export").to_return(
        status: 200,
        body: File.new("test/fixtures/discourse-test-theme.tar.gz"),
        headers: {
          "content-disposition" => 'attachment; filename="testfile.tar.gz"',
        },
      )

    ENV["DISCOURSE_URL"] = "http://my.forum.com"
    ENV["DISCOURSE_API_KEY"] = "abc"

    DiscourseTheme::Watcher.return_immediately!
  end

  DiscourseTheme::Cli.settings_file = Tempfile.new("settings")

  def teardown
    FileUtils.remove_dir(@dir)
  end

  def suppress_output
    original_stdout, original_stderr = $stdout.clone, $stderr.clone
    $stderr.reopen File.new("/dev/null", "w")
    $stdout.reopen File.new("/dev/null", "w")
    yield
  ensure
    $stdout.reopen original_stdout
    $stderr.reopen original_stderr
  end

  def settings
    DiscourseTheme::Config.new(DiscourseTheme::Cli.settings_file)[@dir]
  end

  def test_watch
    args = ["watch", @dir]

    # Stub interactive prompts to always return the first option, or "value"
    DiscourseTheme::UI.stub(:select, ->(question, options) { options[0] }) do
      suppress_output { DiscourseTheme::Cli.new.run(args) }
    end

    assert_requested(@about_stub, times: 1)
    assert_requested(@themes_stub, times: 1)
    assert_requested(@import_stub, times: 1)
    assert_requested(@download_tar_stub, times: 0)

    assert_equal(settings.theme_id, 6)
  end

  def test_watch_with_trailing_slash_in_url_removes_trailing_slash
    ENV["DISCOURSE_URL"] = nil
    args = ["watch", @dir]

    DiscourseTheme::UI.stub(:select, ->(question, options) { options[0] }) do
      DiscourseTheme::UI.stub(:ask, "http://my.forum.com/") do
        DiscourseTheme::UI.stub(:yes?, true) do
          suppress_output { DiscourseTheme::Cli.new.run(args) }
        end
      end
    end

    assert_equal(settings.url, "http://my.forum.com")
  end

  def test_watch_with_basic_auth
    ENV["DISCOURSE_URL"] = "http://username:password@my.forum.com"
    args = ["watch", @dir]

    # Stub interactive prompts to always return the first option, or "value"
    DiscourseTheme::UI.stub(:select, ->(question, options) { options[0] }) do
      suppress_output { DiscourseTheme::Cli.new.run(args) }
    end

    expected_header = { "Authorization" => "Basic #{Base64.strict_encode64("username:password")}" }

    assert_requested(@about_stub.with(headers: expected_header), times: 1)
    assert_requested(@themes_stub.with(headers: expected_header), times: 1)
    assert_requested(@import_stub.with(headers: expected_header), times: 1)
    assert_requested(@download_tar_stub, times: 0)

    assert_equal(settings.theme_id, 6)
  end

  def test_child_theme_prompt
    args = ["watch", @dir]

    questions_asked = []
    DiscourseTheme::UI.stub(
      :select,
      ->(question, options) do
        questions_asked << question
        options[0]
      end,
    ) { suppress_output { DiscourseTheme::Cli.new.run(args) } }
    assert(!questions_asked.join("\n").include?("child theme components"))

    File.write(
      File.join(@dir, "about.json"),
      { components: ["https://github.com/myorg/myrepo"] }.to_json,
    )

    questions_asked = []
    DiscourseTheme::UI.stub(
      :select,
      ->(question, options) do
        questions_asked << question
        options[0]
      end,
    ) { suppress_output { DiscourseTheme::Cli.new.run(args) } }
    assert(questions_asked.join("\n").include?("child theme components"))
  end

  def test_upload
    import_stub =
      stub_request(:post, "http://my.forum.com/admin/themes/import.json").to_return(
        status: 200,
        body: { theme: { id: "1", name: "Existing theme", theme_fields: [] } }.to_json,
      )

    args = ["upload", @dir]

    # Set an existing theme_id, as this is required for upload.
    settings.theme_id = 1

    suppress_output { DiscourseTheme::Cli.new.run(args) }

    assert_requested(@about_stub, times: 1)
    assert_requested(@themes_stub, times: 1)
    assert_requested(import_stub, times: 1)
    assert_requested(@download_tar_stub, times: 0)

    assert_equal(settings.theme_id, 1)
  end

  def test_download
    @download_zip_stub =
      stub_request(:get, "http://my.forum.com/admin/customize/themes/5/export").to_return(
        status: 200,
        body: File.new("test/fixtures/discourse-test-theme.zip"),
        headers: {
          "content-disposition" => 'attachment; filename="testfile.zip"',
        },
      )

    args = ["download", @dir]

    DiscourseTheme::UI.stub(:select, ->(question, options) { options[0] }) do
      DiscourseTheme::UI.stub(:yes?, false) do
        suppress_output { DiscourseTheme::Cli.new.run(args) }
      end
    end

    assert_requested(@about_stub, times: 1)
    assert_requested(@themes_stub, times: 1)
    assert_requested(@import_stub, times: 0)
    assert_requested(@download_tar_stub, times: 1)

    # Check it got downloaded correctly
    Dir.chdir(@dir) do
      folders = Dir.glob("**/*").reject { |f| File.file?(f) }
      assert(folders.sort == %w[assets common locales mobile].sort)

      files = Dir.glob("**/*").reject { |f| File.directory?(f) }
      assert(
        files.sort ==
          %w[
            about.json
            assets/logo.png
            common/body_tag.html
            locales/en.yml
            mobile/mobile.scss
            settings.yml
          ].sort,
      )

      assert(File.read("common/body_tag.html") == "<b>testtheme1</b>")
      assert(
        File.read("mobile/mobile.scss") ==
          "body {background-color: $background_color; font-size: $font-size}",
      )
      assert(File.read("settings.yml") == "somesetting: test")
    end
  end

  def test_download_zip
    @download_zip_stub =
      stub_request(:get, "http://my.forum.com/admin/customize/themes/5/export").to_return(
        status: 200,
        body: File.new("test/fixtures/discourse-test-theme.zip"),
        headers: {
          "content-disposition" => 'attachment; filename="testfile.zip"',
        },
      )

    test_download
  end

  def test_new
    args = ["new", @dir]

    DiscourseTheme::UI.stub(:ask, "my theme name") do
      DiscourseTheme::UI.stub(:yes?, false) do
        suppress_output { DiscourseTheme::Cli.new.run(args) }
      end
    end

    assert_requested(@about_stub, times: 0)
    assert_requested(@themes_stub, times: 0)
    assert_requested(@import_stub, times: 0)
    assert_requested(@download_tar_stub, times: 0)

    # Spot check a few files
    Dir.chdir(@dir) do
      list = files = Dir.glob("**/*").reject { |f| f.start_with?("node_modules/") }
      folders = list.reject { |f| File.file?(f) }
      assert_equal(
        folders.sort,
        %w[
          common
          locales
          node_modules
          javascripts
          javascripts/discourse
          javascripts/discourse/api-initializers
        ].sort,
      )

      files = list.reject { |f| File.directory?(f) }
      assert(files.include?("settings.yml"))
      assert(files.include?("about.json"))
      assert(files.include?("package.json"))
      assert(File.exist?(".eslintrc"))
      assert(File.exist?(".gitignore"))
      assert(File.exist?(".template-lintrc.js"))
      assert(files.include?("locales/en.yml"))
    end
  end
end
