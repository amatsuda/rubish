# frozen_string_literal: true

require_relative 'test_helper'

# Command hashing (set -h, hashall) is on by default, as in bash, so $-
# contains h and `set -o` reports hashall on
class TestHashallDefault < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_dollar_dash_contains_h
    assert_include Rubish::Builtins.current_options, 'h'
  end

  def test_shopt_o_reports_hashall_on
    out = capture_stdout { execute('shopt -o hashall') }
    assert_match(/^hashall\s+on$/, out)
  end

  def test_set_plus_h_turns_it_off
    execute('set +h')
    assert_not_include Rubish::Builtins.current_options, 'h'
    execute('set -h')
  end
end
