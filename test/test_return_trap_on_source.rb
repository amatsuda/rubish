# frozen_string_literal: true

require_relative 'test_helper'

# The RETURN trap runs when a sourced file finishes
class TestReturnTrapOnSource < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('trap - RETURN')
  end

  def test_fires_after_source
    out = capture_stdout { execute("trap 'echo ret' RETURN; . /dev/null; trap - RETURN; . /dev/null; echo end") }
    assert_equal "ret\nend\n", out
  end
end
