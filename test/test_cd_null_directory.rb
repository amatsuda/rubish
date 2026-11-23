# frozen_string_literal: true

require_relative 'test_helper'

# `cd ""` is an error, as in bash
class TestCdNullDirectory < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_empty_argument
    err = capture_stderr { @out = capture_stdout { execute('cd ""; echo $?') } }
    assert_equal "1\n", @out
    assert_match(/cd: null directory/, err)
  end
end
