# frozen_string_literal: true

require_relative 'test_helper'

# `exit` inside a forked part of the shell (a pipeline element, a builtin
# with its own redirections) ends that child with the given status; it
# never surfaces as an "unexpected throw"
class TestExitInForkedChild < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_exit_as_the_last_pipeline_element_sets_the_status
    out, err = run_shell('echo a | exit 5; echo $?')
    assert_equal "5\n", out
    assert_equal '', err
  end

  def test_exit_as_the_first_pipeline_element_is_quiet
    out, err = run_shell('exit 5 | echo a; echo $?')
    assert_equal "a\n0\n", out
    assert_equal '', err
  end

  def test_logout_with_a_redirection
    out, err = run_shell('logout 2>&1; echo $?')
    assert_match(/not login shell/, out)
    assert_equal '', err
  end
end

class TestExitInForkedChild
  def test_function_calling_exit_in_a_pipeline
    out, err = run_shell('f() { exit 3; }; echo a | f; echo $?')
    assert_equal "3\n", out
    assert_equal '', err
  end
end
