# frozen_string_literal: true

require_relative 'test_helper'

# echo always appends exactly one newline, even when the text ends with one
class TestEchoTrailingNewline < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_argument_ending_in_newline_keeps_both_newlines
    out = capture_stdout { execute(%q(echo $'a\n')) }
    assert_equal "a\n\n", out
  end

  def test_argument_of_only_newlines
    out = capture_stdout { execute(%q(echo $'\n\n\n')) }
    assert_equal "\n\n\n\n", out
  end

  def test_variable_ending_in_newline
    execute(%q(x=$'line\n'))
    out = capture_stdout { execute('echo "$x"') }
    assert_equal "line\n\n", out
  end

  def test_dash_n_still_suppresses_newline
    out = capture_stdout { execute(%q(echo -n $'a\n')) }
    assert_equal "a\n", out
  end

  def test_dash_e_escape_ending_in_newline
    out = capture_stdout { execute('echo -e "a\\n"') }
    assert_equal "a\n\n", out
  end
end
