# frozen_string_literal: true

require_relative 'test_helper'

# `exit` with no argument exits with the status of the last command ($?)
class TestExitDefaultStatus < Test::Unit::TestCase
  RUBISH = File.expand_path('../exe/rubish', __dir__)

  def run_rubish(script)
    pid = Process.spawn(RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), RUBISH, '-c', script,
                        out: File::NULL, err: File::NULL)
    Process.wait(pid)
    $?.exitstatus
  end

  def test_exit_without_argument_uses_last_status
    assert_equal 1, run_rubish('false; exit')
  end

  def test_exit_without_argument_after_success_is_zero
    assert_equal 0, run_rubish('true; exit')
  end

  def test_exit_with_argument_still_wins
    assert_equal 5, run_rubish('false; exit 5')
  end

  def test_exit_builtin_throws_nil_when_no_argument
    assert_nil catch(:exit) { Rubish::Builtins.run('exit', []) }
  end
end
