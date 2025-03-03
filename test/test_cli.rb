# frozen_string_literal: true

require "test_helper"
require "base64"
require "mocha/minitest"

class TestCli < Minitest::Test
  def setup
    WebMock.reset!
    @dir = Dir.mktmpdir
    @spec_dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@spec_dir, "/spec"))
    @discourse_dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@discourse_dir, "/lib"))
    File.new(File.join(@discourse_dir, "lib/discourse.rb"), "w")

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
          themes: [
            {
              id: 0,
              name: "Some theme",
              theme_fields: [
                {
                  "name" => "0001-rename-settings",
                  "target" => "migrations",
                  "value" => "export default function migrate(settings) {\n  return settings;\n}\n",
                  "type_id" => 6,
                  "migrated" => true,
                },
              ],
            },
            { id: 1, name: "Magic theme" },
            { id: 5, name: "Amazing theme" },
          ],
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
    [@dir, @spec_dir, @discourse_dir].each { |dir| FileUtils.remove_dir(dir) }
  end

  def capture_output(output_name)
    previous_output = output_name == :stdout ? $stdout : $stderr

    io = StringIO.new
    output_name == :stdout ? $stdout = io : $stderr = io

    yield
    io.string
  ensure
    output_name == :stdout ? $stdout = previous_output : $stderr = previous_output
  end

  def capture_stdout(&block)
    capture_output(:stdout, &block)
  end

  def capture_stderr(&block)
    capture_output(:stderr, &block)
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

  def settings(setting_dir = @dir)
    DiscourseTheme::Config.new(DiscourseTheme::Cli.settings_file)[setting_dir]
  end

  def wait_for(timeout, &blk)
    till = Time.now + (timeout.to_f / 1000)

    while !blk.call
      raise "Timeout waiting for block to return true" if Time.now > till

      sleep 0.001
    end
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

  def test_watch_uploads_theme_with_skip_migrations_params_when_user_does_not_want_to_run_migrations_after_prompted
    args = ["watch", @dir]

    FileUtils.mkdir_p(File.join(@dir, "migrations", "settings"))

    File.write(File.join(@dir, "migrations", "settings", "0001-rename-settings.js"), <<~JS)
    export default function migrate(settings) {
      return settings;
    }
    JS

    File.write(File.join(@dir, "migrations", "settings", "0002-rename-settings.js"), <<~JS)
    export default function migrate(settings) {
      return settings;
    }
    JS

    DiscourseTheme::UI.stub(
      :select,
      ->(question, options) do
        case question
        when "How would you like to sync this theme?"
          options[0]
        when "Would you like to run the following pending theme migration(s): migrations/settings/0002-rename-settings.js\n  Select 'No' if you are in the midst of adding or modifying theme migration(s).\n"
          options[0]
        end
      end,
    ) { DiscourseTheme::Cli.new.run(args) }

    assert_requested(:post, "http://my.forum.com/admin/themes/import.json", times: 1) do |req|
      req.body.include?("skip_migrations")
    end
  end

  def test_watch_uploads_theme_without_skip_migrations_params_when_user_wants_to_run_migrations_after_prompted
    args = ["watch", @dir]

    FileUtils.mkdir_p(File.join(@dir, "migrations", "settings"))

    File.write(File.join(@dir, "migrations", "settings", "0001-rename-settings.js"), <<~JS)
    export default function migrate(settings) {
      return settings;
    }
    JS

    File.write(File.join(@dir, "migrations", "settings", "0002-rename-settings.js"), <<~JS)
    export default function migrate(settings) {
      return settings;
    }
    JS

    DiscourseTheme::UI.stub(
      :select,
      ->(question, options) do
        case question
        when "How would you like to sync this theme?"
          options[0]
        when "Would you like to run the following pending theme migration(s): migrations/settings/0002-rename-settings.js\n  Select 'No' if you are in the midst of adding or modifying theme migration(s).\n"
          options[1]
        end
      end,
    ) { suppress_output { DiscourseTheme::Cli.new.run(args) } }

    assert_requested(:post, "http://my.forum.com/admin/themes/import.json", times: 1) do |req|
      !req.body.include?("skip_migrations")
    end
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
    DiscourseTheme::Scaffold.expects(:online?).returns(false)
    DiscourseTheme::Scaffold
      .expects(:skeleton_dir)
      .at_least_once
      .returns(File.join(File.expand_path(File.dirname(__FILE__)), "/fixtures/skeleton-lite"))

    DiscourseTheme::UI
      .stubs(:ask)
      .with("What would you like to call your theme?", anything)
      .returns("my theme")
    DiscourseTheme::UI.stubs(:ask).with("Who is authoring the theme?", anything).returns("Jane")
    DiscourseTheme::UI
      .stubs(:ask)
      .with("How would you describe this theme?", anything)
      .returns("A magical theme")
    DiscourseTheme::UI.stubs(:yes?).with("Is this a component?").returns(false)
    DiscourseTheme::UI
      .stubs(:yes?)
      .with("Would you like to start 'watching' this theme?")
      .returns(false)

    suppress_output { Dir.chdir(@dir) { DiscourseTheme::Cli.new.run(%w[new foo]) } }

    Dir.chdir(@dir + "/foo") do
      assert(File.exist?("javascripts/discourse/api-initializers/my-theme.gjs"))

      assert_equal(
        "A magical theme",
        YAML.safe_load(File.read("locales/en.yml"))["en"]["theme_metadata"]["description"],
      )

      about = JSON.parse(File.read("about.json"))
      assert_equal("my theme", about["name"])
      assert_equal("Jane", about["authors"])
      assert_nil(about["component"])
      assert_equal({}, about["color_schemes"])

      assert_match("Copyright (c) Jane", File.read("LICENSE"))
      assert_match("# my theme\n", File.read("README.md"))
      assert(File.exist?(".github/test"))
    end
  end

  def mock_rspec_local_discourse_commands(dir, spec_dir, rspec_path: "/spec", headless: true)
    Kernel.expects(:exec).with(
      anything,
      "cd #{dir} && #{headless ? "" : DiscourseTheme::CliCommands::Rspec::SELENIUM_HEADFUL_ENV} bundle exec rspec #{File.join(spec_dir, rspec_path)}",
    )
  end

  def mock_rspec_docker_commands(
    verbose:,
    setup_commands:,
    rspec_path: "/spec",
    container_state: nil,
    headless: true
  )
    DiscourseTheme::CliCommands::Rspec
      .expects(:execute)
      .with(
        command:
          "docker ps -a --filter name=#{DiscourseTheme::CliCommands::Rspec.discourse_test_docker_container_name} --format '{{json .}}'",
      )
      .returns(
        (
          if container_state
            %({"Names":"#{DiscourseTheme::CliCommands::Rspec.discourse_test_docker_container_name}","State":"#{container_state}"})
          else
            ""
          end
        ),
      )

    if setup_commands
      DiscourseTheme::CliCommands::Rspec
        .expects(:execute)
        .with(
          command:
            "docker ps -a -q --filter name=#{DiscourseTheme::CliCommands::Rspec::DISCOURSE_TEST_DOCKER_CONTAINER_NAME_PREFIX}",
        )
        .returns("12345\n678910")

      DiscourseTheme::CliCommands::Rspec.expects(:execute).with(command: "docker stop 12345 678910")
      DiscourseTheme::CliCommands::Rspec.expects(:execute).with(
        command: "docker rm -f 12345 678910",
      )

      DiscourseTheme::CliCommands::Rspec.expects(:execute).with(
        command: <<~COMMAND.squeeze(" "),
          docker run -d \
            -p 31337:31337 \
            --add-host host.docker.internal:host-gateway \
            --entrypoint=/sbin/boot \
            --name=#{DiscourseTheme::CliCommands::Rspec.discourse_test_docker_container_name} \
            --pull=always \
            -v #{DiscourseTheme::CliCommands::Rspec::DISCOURSE_THEME_TEST_TMP_DIR}:/tmp \
            discourse/discourse_test:release
        COMMAND
        message: "Creating discourse/discourse_test:release Docker container...",
        stream: verbose,
      )

      DiscourseTheme::CliCommands::Rspec.expects(:execute).with(
        command:
          "docker exec -u discourse:discourse #{DiscourseTheme::CliCommands::Rspec.discourse_test_docker_container_name} ruby script/docker_test.rb --no-tests --checkout-ref origin/tests-passed",
        message: "Checking out latest Discourse source code...",
        stream: verbose,
      )

      DiscourseTheme::CliCommands::Rspec.expects(:execute).with(
        command:
          "docker exec -e SKIP_MULTISITE=1 -u discourse:discourse #{DiscourseTheme::CliCommands::Rspec.discourse_test_docker_container_name} bundle exec rake docker:test:setup",
        message: "Setting up Discourse test environment...",
        stream: verbose,
      )

      DiscourseTheme::CliCommands::Rspec.expects(:execute).with(
        command:
          "docker exec -u discourse:discourse #{DiscourseTheme::CliCommands::Rspec.discourse_test_docker_container_name} bin/ember-cli --build",
        message: "Building Ember CLI assets...",
        stream: verbose,
      )
    end

    FileUtils.expects(:rm_rf).with(
      File.join(
        DiscourseTheme::CliCommands::Rspec::DISCOURSE_THEME_TEST_TMP_DIR,
        File.basename(@spec_dir),
      ),
    )

    FileUtils.expects(:cp_r).with(
      @spec_dir,
      DiscourseTheme::CliCommands::Rspec::DISCOURSE_THEME_TEST_TMP_DIR,
    )

    if !headless
      fake_ip = "123.456.789"

      DiscourseTheme::CliCommands::Rspec
        .expects(:execute)
        .with(
          command:
            "docker inspect #{DiscourseTheme::CliCommands::Rspec.discourse_test_docker_container_name} --format '{{.NetworkSettings.IPAddress}}'",
        )
        .returns(fake_ip)

      DiscourseTheme::CliCommands::Rspec
        .expects(:start_chromedriver)
        .with(allowed_ip: fake_ip, allowed_origin: "host.docker.internal")
        .returns(mock(uri: URI("http://localhost:9515")))

      DiscourseTheme::CliCommands::Rspec.expects(:execute).with(
        command:
          "docker exec -e SELENIUM_HEADLESS=0 -e CAPYBARA_SERVER_HOST=0.0.0.0 -e CAPYBARA_REMOTE_DRIVER_URL=http://host.docker.internal:9515 -t -u discourse:discourse #{DiscourseTheme::CliCommands::Rspec.discourse_test_docker_container_name} bundle exec rspec #{@spec_dir}#{rspec_path}",
        stream: true,
      )
    else
      DiscourseTheme::CliCommands::Rspec.expects(:execute).with(
        command:
          "docker exec -t -u discourse:discourse #{DiscourseTheme::CliCommands::Rspec.discourse_test_docker_container_name} bundle exec rspec #{@spec_dir}#{rspec_path}",
        stream: true,
      )
    end
  end

  def run_cli_rspec_with_docker(cli, args)
    DiscourseTheme::UI.stub(:yes?, false) { suppress_output { cli.run(args) } }
  end

  def run_cli_rspec_with_local_discourse_repository(
    cli,
    args,
    local_discourse_directory,
    suppress_output: true
  )
    DiscourseTheme::UI.stub(:ask, local_discourse_directory) do
      DiscourseTheme::UI.stub(:yes?, true) do
        if suppress_output
          suppress_output { cli.run(args) }
        else
          cli.run(args)
        end
      end
    end
  end

  def test_rspec_using_local_discourse_repository
    args = ["rspec", @spec_dir]

    cli = DiscourseTheme::Cli.new

    mock_rspec_local_discourse_commands(@discourse_dir, @spec_dir)
    run_cli_rspec_with_local_discourse_repository(cli, args, @discourse_dir)

    assert_equal(settings(@spec_dir).local_discourse_directory, @discourse_dir)
  end

  def test_rspec_using_local_discourse_repository_dir_path_to_custom_rspec_folder
    args = ["rspec", File.join(@spec_dir, "/spec/system")]

    cli = DiscourseTheme::Cli.new

    mock_rspec_local_discourse_commands(@discourse_dir, @spec_dir, rspec_path: "/spec/system")
    run_cli_rspec_with_local_discourse_repository(cli, args, @discourse_dir)

    assert_equal(settings(@spec_dir).local_discourse_directory, @discourse_dir)
  end

  def test_rspec_using_local_discourse_repository_dir_path_to_custom_rspec_file
    args = ["rspec", File.join(@spec_dir, "/spec/system/some_spec.rb")]

    cli = DiscourseTheme::Cli.new

    mock_rspec_local_discourse_commands(
      @discourse_dir,
      @spec_dir,
      rspec_path: "/spec/system/some_spec.rb",
    )

    run_cli_rspec_with_local_discourse_repository(cli, args, @discourse_dir)

    assert_equal(settings(@spec_dir).local_discourse_directory, @discourse_dir)
  end

  def test_rspec_using_local_discourse_repository_dir_path_to_custom_rspec_file_with_line_number
    args = ["rspec", File.join(@spec_dir, "/spec/system/some_spec.rb:44")]

    cli = DiscourseTheme::Cli.new

    mock_rspec_local_discourse_commands(
      @discourse_dir,
      @spec_dir,
      rspec_path: "/spec/system/some_spec.rb:44",
    )

    run_cli_rspec_with_local_discourse_repository(cli, args, @discourse_dir)

    assert_equal(settings(@spec_dir).local_discourse_directory, @discourse_dir)
  end

  def test_rspec_using_local_discourse_repository_with_headful_option
    args = ["rspec", @spec_dir, "--headful"]

    cli = DiscourseTheme::Cli.new

    mock_rspec_local_discourse_commands(@discourse_dir, @spec_dir, headless: false)
    run_cli_rspec_with_local_discourse_repository(cli, args, @discourse_dir)
  end

  def test_rspec_using_local_discourse_repository_with_non_existence_directory
    args = ["rspec", @spec_dir]

    cli = DiscourseTheme::Cli.new

    output =
      capture_stdout do
        run_cli_rspec_with_local_discourse_repository(
          cli,
          args,
          "/non/existence/directory",
          suppress_output: false,
        )
      end

    assert_match("/non/existence/directory does not exist", output)
    assert_nil(settings(@spec_dir).local_discourse_directory)
  end

  def test_rspec_using_local_discourse_repository_with_directory_that_is_not_a_discourse_repository
    args = ["rspec", @spec_dir]

    cli = DiscourseTheme::Cli.new

    output =
      capture_stdout do
        run_cli_rspec_with_local_discourse_repository(cli, args, @dir, suppress_output: false)
      end

    assert_match("#{@dir} is not a Discourse repository", output)
  end

  def test_rspec_using_docker
    args = ["rspec", @spec_dir]

    cli = DiscourseTheme::Cli.new
    mock_rspec_docker_commands(verbose: false, setup_commands: true)

    run_cli_rspec_with_docker(cli, args)
  end

  def test_rspec_using_docker_directory_without_spec_folder
    args = ["rspec", @spec_dir]
    FileUtils.rm_rf(File.join(@spec_dir, "/spec"))

    cli = DiscourseTheme::Cli.new
    cli.expects(:execute).never

    run_cli_rspec_with_docker(cli, args)
  end

  def test_rspec_using_docker_with_headful_option
    args = ["rspec", @spec_dir, "--headful"]

    cli = DiscourseTheme::Cli.new
    mock_rspec_docker_commands(verbose: false, setup_commands: true, headless: false)

    run_cli_rspec_with_docker(cli, args)
  end

  def test_rspec_using_docker_with_verbose_option
    args = ["rspec", @spec_dir, "--verbose"]

    cli = DiscourseTheme::Cli.new
    mock_rspec_docker_commands(verbose: true, setup_commands: true)

    run_cli_rspec_with_docker(cli, args)
  end

  def test_rspec_using_docker_with_rebuild_option
    args = ["rspec", @spec_dir, "--rebuild"]

    cli = DiscourseTheme::Cli.new

    mock_rspec_docker_commands(verbose: false, setup_commands: true, container_state: "running")

    run_cli_rspec_with_docker(cli, args)
  end

  def test_rspec_using_docker_when_docker_container_is_already_running
    args = ["rspec", @spec_dir]

    cli = DiscourseTheme::Cli.new

    mock_rspec_docker_commands(verbose: false, setup_commands: false, container_state: "running")

    run_cli_rspec_with_docker(cli, args)
  end

  def test_rspec_using_docker_with_dir_path_to_rspec_folder
    args = ["rspec", File.join(@spec_dir, "/spec")]

    cli = DiscourseTheme::Cli.new

    mock_rspec_docker_commands(verbose: false, setup_commands: false, container_state: "running")

    run_cli_rspec_with_docker(cli, args)

    assert_equal(settings(@spec_dir).local_discourse_directory, "")
  end

  def test_rspec_using_docker_with_dir_path_to_custom_rspec_folder
    args = ["rspec", File.join(@spec_dir, "/spec/system")]

    cli = DiscourseTheme::Cli.new

    mock_rspec_docker_commands(
      verbose: false,
      setup_commands: false,
      rspec_path: "/spec/system",
      container_state: "running",
    )

    run_cli_rspec_with_docker(cli, args)

    assert_equal(settings(@spec_dir).local_discourse_directory, "")
  end

  def test_rspec_using_docker_with_dir_path_to_rspec_file
    args = ["rspec", File.join(@spec_dir, "/spec/system/some_spec.rb")]

    cli = DiscourseTheme::Cli.new

    mock_rspec_docker_commands(
      verbose: false,
      setup_commands: false,
      rspec_path: "/spec/system/some_spec.rb",
      container_state: "running",
    )

    run_cli_rspec_with_docker(cli, args)

    assert_equal(settings(@spec_dir).local_discourse_directory, "")
  end

  def test_rspec_using_docker_with_dir_path_to_rspec_file_with_line_number
    args = ["rspec", File.join(@spec_dir, "/spec/system/some_spec.rb:3")]

    cli = DiscourseTheme::Cli.new

    mock_rspec_docker_commands(
      verbose: false,
      setup_commands: false,
      rspec_path: "/spec/system/some_spec.rb:3",
      container_state: "running",
    )

    run_cli_rspec_with_docker(cli, args)

    assert_equal(settings(@spec_dir).local_discourse_directory, "")
  end
end
