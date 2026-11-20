# frozen_string_literal: true

require_relative 'test_helper'

# `exit N` inside a subshell terminates only the subshell, with status N
class TestSubshellExit < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  def test_exit_in_subshell_sets_subshell_status
    capture_stderr { execute('(exit 7)') }
    assert_equal 7, last_status
  end

  def test_exit_in_subshell_does_not_exit_parent_shell
    out = capture_output { execute('(exit 3); echo "status=$?"') }
    assert_equal "status=3\n", out
  end

  def test_exit_in_subshell_stops_remaining_subshell_commands
    Dir.mktmpdir('rubish_subshell_exit') do |dir|
      out = File.join(dir, 'out.txt')
      execute("(echo a; exit 2; echo b) > #{out}")
      assert_equal "a\n", File.read(out)
      assert_equal 2, last_status
    end
  end

  def test_exit_without_status_in_subshell_uses_last_status
    capture_stderr { execute('(false; exit)') }
    assert_equal 1, last_status
  end

  def test_subshell_status_in_pipeline
    out = capture_output { execute('(exit 3) | cat; echo "${PIPESTATUS[0]}"') }
    assert_equal "3\n", out
  end

  def test_failing_subshell_in_pipeline_with_pipefail
    execute('set -o pipefail')
    capture_output { execute('(false) | cat') }
    assert_equal 1, last_status
  ensure
    execute('set +o pipefail')
  end
end
