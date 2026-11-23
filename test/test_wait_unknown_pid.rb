# frozen_string_literal: true

require_relative 'test_helper'

# `wait N` for a pid that is not a child fails with 127, as in bash
class TestWaitUnknownPid < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_status_127
    err = capture_stderr { @out = capture_stdout { execute('wait 999999; echo $?') } }
    assert_equal "127\n", @out
    assert_match(/wait: pid 999999 is not a child of this shell/, err)
  end
end
