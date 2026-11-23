# frozen_string_literal: true

require_relative 'test_helper'

# ${!name} where name holds a number expands that positional parameter
class TestIndirectPositional < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_indirect_through_a_number
    out = capture_stdout { execute(%q{set -- a b c; n=2; echo "${!n}"; OPTIND=3; echo "${!OPTIND}"; m=9; echo "[${!m}]"}) }
    assert_equal "b\nc\n[]\n", out
  end
end
