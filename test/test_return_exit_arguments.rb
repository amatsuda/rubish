# frozen_string_literal: true

require_relative 'test_helper'

# return and exit with too many or non-numeric arguments report the problem
# and do not act, as bash 5.3 does
class TestReturnExitArguments < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read, $?.exitstatus]
  ensure
    err_r&.close
  end

  def test_return_with_too_many_arguments
    out, err, status = run_shell('f() { return 1 2 3; echo in; }; f; echo $?')
    assert_equal "1\n", out
    assert_match(/return: too many arguments/, err)
    assert_equal 0, status
  end

  def test_exit_with_a_non_numeric_argument_does_not_exit
    out, err, = run_shell('exit abc; echo "not $?"')
    assert_equal "not 2\n", out
    assert_match(/exit: abc: numeric argument required/, err)
  end

  def test_exit_with_too_many_arguments_exits_a_non_interactive_shell
    # bash 5.3 goes on only in an interactive shell; -c exits with 1
    out, err, status = run_shell('exit 1 2; echo "not $?"')
    assert_equal '', out
    assert_equal 1, status
    assert_match(/exit: too many arguments/, err)
  end
end
