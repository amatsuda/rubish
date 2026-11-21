# frozen_string_literal: true

require_relative 'test_helper'

# PIPESTATUS is unset until a pipeline (or command) has run, as in bash
class TestPipestatusInitial < Test::Unit::TestCase
  def test_empty_before_any_command
    repl = Rubish::REPL.new
    out = capture_stdout { repl.send(:execute, 'echo "[${PIPESTATUS[@]}] [${#PIPESTATUS[@]}]"') }
    assert_equal "[] [0]\n", out
  end

  def test_set_after_a_pipeline
    repl = Rubish::REPL.new
    repl.send(:execute, 'true | false')
    out = capture_stdout { repl.send(:execute, 'echo "${PIPESTATUS[@]}"') }
    assert_equal "0 1\n", out
  end
end
