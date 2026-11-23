# frozen_string_literal: true

require_relative 'test_helper'

# Redirections apply in order: `2>&1 1>&2` makes stderr follow stdout and
# then stdout follow that same place; `1>&2 2>&1` sends both to stderr
class TestDupOrderStdoutToStderr < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_stderr_to_stdout_then_stdout_to_stderr_in_a_pipeline
    assert_equal ["out\n", ''], run_shell('echo out 2>&1 1>&2 | cat')
  end

  def test_stdout_to_stderr_then_stderr_to_stdout_in_a_pipeline
    assert_equal ['', "out\n"], run_shell('echo out 1>&2 2>&1 | cat')
  end

  def test_stderr_to_stdout_then_stdout_to_stderr_without_a_pipe
    assert_equal ["out\n", ''], run_shell('echo out 2>&1 1>&2')
  end
end
