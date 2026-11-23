# frozen_string_literal: true

require_relative 'test_helper'

# `kill` without arguments prints bash's usage and fails with 2
class TestKillUsageStatus < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_no_arguments
    err = capture_stderr { @out = capture_stdout { execute('kill; echo $?') } }
    assert_equal "2\n", @out
    assert_equal "kill: usage: kill [-s sigspec | -n signum | -sigspec] pid | jobspec ... or kill -l [sigspec]\n", err
  end
end
