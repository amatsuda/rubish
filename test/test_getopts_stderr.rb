# frozen_string_literal: true

require_relative 'test_helper'

# getopts reports an illegal option on stderr, so `2>/dev/null` silences it
class TestGetoptsStderr < Test::Unit::TestCase
  def test_error_goes_to_stderr
    repl = Rubish::REPL.new
    err = nil
    out = capture_stdout { err = capture_stderr { repl.send(:execute, 'set -- -x; getopts "a" o; echo "o=$o"') } }
    assert_equal "o=?\n", out
    assert_match(/illegal option/, err)
  end
end
