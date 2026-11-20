# frozen_string_literal: true

require_relative 'test_helper'

# `exec` with redirections must work when it is not the only command on the
# line (inside a list, after `;` or `&&`), not just as a bare top-level command.
class TestExecInList < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_exec_in_list')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def test_exec_stderr_redirect_followed_by_command
    err_file = File.join(@tempdir, 'err.txt')
    # exec modifies the shell's own fds, so run in a child process
    pid = fork do
      Rubish::REPL.new.send(:execute, "exec 2> #{err_file}; echo oops >&2")
      exit!(0)
    end
    Process.wait(pid)
    assert_equal "oops\n", File.read(err_file)
  end

  def test_exec_redirect_only_in_list_does_not_abort_the_list
    out = capture_stdout { execute('true; exec 3>/dev/null; echo after') }
    assert_equal "after\n", out
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end
end
