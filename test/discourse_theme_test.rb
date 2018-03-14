require "test_helper"

class DiscourseThemeTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::DiscourseTheme::VERSION
  end

  # this is going to be fun, I want to add tests but we got to make
  # sure this does not become mock central
end
