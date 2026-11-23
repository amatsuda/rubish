# frozen_string_literal: true

require_relative 'test_helper'

# `alias name` for an undefined alias reports on stderr and fails
class TestAliasNotFoundStatus < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_status_and_message
    err = capture_stderr { @out = capture_stdout { execute('alias nosuch; echo $?') } }
    assert_equal "1\n", @out
    assert_match(/alias: nosuch: not found/, err)
  end
end
