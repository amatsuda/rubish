# frozen_string_literal: true

require_relative 'test_helper'

class TestSetOInvalid < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  # set -o with an unknown option is an error with status 2
  def test_set_o_unknown_option
    err = capture_stderr { execute('set -o nosuchopt_xyz') }
    assert_match(/nosuchopt_xyz: invalid option name/, err)
    assert_equal 2, @repl.instance_variable_get(:@last_status)
  end
end
