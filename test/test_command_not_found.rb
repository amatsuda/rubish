# frozen_string_literal: true

require_relative 'test_helper'

# An unknown command is diagnosed in the shell process, with status 127
class TestCommandNotFound < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    Rubish::Command.clear_command_cache
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  def test_unknown_command_reports_not_found_with_status_127
    err = capture_stderr { execute('nosuchcmd_rubish_xyz') }
    assert_match(/nosuchcmd_rubish_xyz: command not found/, err)
    assert_equal 127, last_status
  end

  def test_unknown_command_in_list_does_not_stop_following_command
    out = capture_output { execute('nosuchcmd_rubish_xyz; echo next') }
    assert_match(/command not found/, out)
    assert_match(/next\n/, out)
  end

  def test_suggestion_dictionary_is_cached_in_the_shell_process
    capture_stderr { execute('nosuchcmd_rubish_xyz') }
    cache = Rubish::Command.instance_variable_get(:@available_commands_cache)
    assert_not_nil cache, 'PATH scan for suggestions should be memoized in the parent, not redone per failure'
  end

  def test_unknown_command_with_path_reports_not_found
    err = capture_stderr { execute('/nonexistent_dir_rubish/cmd') }
    assert_match(/command not found|No such file/, err)
    assert_equal 127, last_status
  end
end
