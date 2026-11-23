# frozen_string_literal: true

require_relative 'test_helper'

# `--` ends option parsing in getopts and OPTIND moves past it
class TestGetoptsDoubleDash < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_optind_points_past_the_double_dash
    out = capture_stdout { execute('set -- -a -- -b; while getopts "ab" o; do echo $o; done; echo $OPTIND') }
    assert_equal "a\n3\n", out
  end
end
