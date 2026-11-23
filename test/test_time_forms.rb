# frozen_string_literal: true

require_relative 'test_helper'

# `time` on its own, on a subshell, and on an assignment
class TestTimeForms < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read, $?.exitstatus]
  ensure
    err_r&.close
  end

  def test_time_alone_reports
    _out, err, status = run_shell('time')
    assert_match(/real/, err)
    assert_equal 0, status
  end

  def test_time_of_a_subshell
    out, err, status = run_shell('time (echo sub)')
    assert_equal "sub\n", out
    assert_match(/real/, err)
    assert_equal 0, status
  end

  def test_time_of_an_assignment_keeps_the_assignment
    out, = run_shell('x=1; time x=2 2>/dev/null; echo $x')
    assert_equal "2\n", out
  end
end
