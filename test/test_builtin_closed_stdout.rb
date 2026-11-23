# frozen_string_literal: true

require_relative 'test_helper'

# A builtin whose stdout was closed with `>&-` fails with a write error
# instead of crashing the shell
class TestBuiltinClosedStdout < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_echo_to_a_closed_stdout
    out, err = run_shell('echo x >&-; echo "status $?"')
    assert_equal "status 1\n", out
    assert_match(/echo: write error: Bad file descriptor/, err)
    assert_no_match(/IOError|closed stream/, err)
  end

  def test_closed_stderr_is_quiet
    out, err = run_shell('echo y 2>&-; echo "status $?"')
    assert_equal "y\nstatus 0\n", out
    assert_equal '', err
  end
end
