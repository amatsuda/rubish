# frozen_string_literal: true

require_relative 'test_helper'

# Redirections may come before the command name: `</dev/null cat`, `2>/dev/null ls x`
class TestLeadingRedirections < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_input_redirection_first
    assert_equal ["0\n", ''], run_shell("</dev/null cat | wc -c | tr -d ' '")
  end

  def test_stderr_redirection_first
    out, err = run_shell('2>/dev/null ls /nonexistent_dir_x; echo "status $?"')
    assert_equal "status 1\n", out
    assert_equal '', err
  end

  def test_redirection_before_a_builtin
    out, = run_shell('>/dev/null echo hidden; echo shown')
    assert_equal "shown\n", out
  end
end
