# frozen_string_literal: true

require_relative 'test_helper'

# OPTIND starts at 1, as in bash
class TestOptindDefault < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_initial_value
    out = capture_stdout { execute('echo "[$OPTIND]"') }
    assert_equal "[1]\n", out
  end
end
