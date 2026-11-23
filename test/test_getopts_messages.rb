# frozen_string_literal: true

require_relative 'test_helper'

# getopts reports in the shell's name, like bash's "bash: illegal option -- x"
class TestGetoptsMessages < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_illegal_option
    err = capture_stderr { capture_stdout { execute('set -- -x; getopts "ab" o') } }
    assert_equal "rubish: illegal option -- x\n", err
  end

  def test_missing_argument
    err = capture_stderr { capture_stdout { execute('set -- -a; getopts "a:" o') } }
    assert_equal "rubish: option requires an argument -- a\n", err
  end
end
