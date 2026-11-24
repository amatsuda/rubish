# frozen_string_literal: true

require_relative 'test_helper'

# Heredoc delimiters can be backslash-quoted, partly quoted, or contain `-`
class TestHeredocDelimiterForms < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_backslash_quoted_delimiter_disables_expansion
    assert_equal "$x not expanded \\$\n", run_shell("x=1; cat <<\\EOF\n$x not expanded \\$\nEOF\n")
  end

  def test_partly_quoted_delimiter_disables_expansion
    assert_equal "quoted $x\n", run_shell("x=1; cat <<EO\"F\"\nquoted $x\nEOF\n")
  end

  def test_delimiter_with_dash
    assert_equal "odd\n", run_shell("cat <<E_O-F\nodd\nE_O-F\n")
  end
end
