# frozen_string_literal: true

require_relative 'test_helper'

# A backslash in a glob pattern quotes the next character (${x//\"/Q}, case patterns)
class TestPatternBackslash < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    Rubish::Builtins.unset(%w[x])
  end

  def test_escaped_double_quote_in_replacement_pattern
    execute(%q(x='a"b"c'))
    out = capture_stdout { execute('echo "${x//\"/Q}"') }
    assert_equal "aQbQc\n", out
  end

  def test_escaped_star_matches_literal_star
    execute("x='a*b'")
    out = capture_stdout { execute('echo "${x/\*/STAR}"') }
    assert_equal "aSTARb\n", out
  end

  def test_prefix_removal_with_escaped_dot
    execute("x='file.tar.gz'")
    out = capture_stdout { execute('echo "${x%\.*}"') }
    assert_equal "file.tar\n", out
  end
end
