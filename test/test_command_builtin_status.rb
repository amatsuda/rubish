# frozen_string_literal: true

require_relative 'test_helper'

# `command cmd` has cmd's exit status, and errexit sees it
class TestCommandBuiltinStatus < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', script, err: File::NULL], &:read)
    [out, $?.exitstatus]
  end

  def test_status_of_a_failing_command
    assert_equal ["1\n", 0], run_shell('command false; echo $?')
  end

  def test_status_of_a_missing_command
    assert_equal ["127\n", 0], run_shell('command nosuch_cmd_q; echo $?')
  end

  def test_errexit_applies
    assert_equal ['', 1], run_shell('set -e; command false; echo not')
  end

  def test_v_names_a_keyword
    assert_equal ["if\n", 0], run_shell('command -v if')
  end
end
