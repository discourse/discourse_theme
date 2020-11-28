# frozen_string_literal: true
require "test_helper"
require "tempfile"

class TestConfig < Minitest::Test
  def new_temp_filename
    f = Tempfile.new
    f.close
    filename = f.path
    f.unlink
    filename
  end

  def capture_stderr
    before = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = before
  end

  def test_config_serialization
    f = Tempfile.new
    f.write <<~CONF
      "/a/b/c":
        api_key: abc
        url: http://test.com
    CONF
    f.close

    config = DiscourseTheme::Config.new f.path

    settings = config["/a/b/c"]
    assert_equal("abc", settings.api_key)
    assert_equal("http://test.com", settings.url)
  ensure
    f.unlink
  end

  def test_corrupt_settings
    filename = new_temp_filename

    File.write(filename, "x\nb:")

    config = nil
    captured = capture_stderr do
      config = DiscourseTheme::Config.new filename
    end

    assert(captured.include? "ERROR")

  ensure
    File.unlink filename
  end

  def test_can_amend_settings
    filename = new_temp_filename

    config = DiscourseTheme::Config.new filename
    settings = config["/test"]
    settings.api_key = "abc"

    config = DiscourseTheme::Config.new filename
    assert_nil(config["/test"].url)
    assert_equal("abc", config["/test"].api_key)

  ensure
    File.unlink(filename)
  end

  def test_config_can_be_written
    filename = new_temp_filename

    config = DiscourseTheme::Config.new filename
    config["/a/b/c"].url = "http://a.com"
    config["/a/b/c"].api_key = "bla"

    config = DiscourseTheme::Config.new filename
    settings = config["/a/b/c"]

    assert_equal("bla", settings.api_key)
    assert_equal("http://a.com", settings.url)

  ensure
    File.unlink(filename)
  end
end
