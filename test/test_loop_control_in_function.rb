# frozen_string_literal: true

require_relative 'test_helper'

# break or continue in a function body with no loop in it is only a warning (bash)
class TestLoopControlInFunction < Test::Unit::TestCase
  def test_warning_and_loop_goes_on
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'f() { continue; echo in_f; }; for i in 1 2; do f; echo $i; done; g() { break; }; for j in a b; do g; echo $j; done', err: err_w], &:read)
    err_w.close
    assert_equal "in_f\n1\nin_f\n2\na\nb\n", out
    assert_equal 4, err_r.read.lines.grep(/only meaningful in a .for., .while., or .until. loop/).size
  ensure
    err_r&.close
  end

  def test_loop_inside_the_function_still_works
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'f() { for k in 1 2 3; do [[ $k == 2 ]] && break; echo $k; done; }; f', err: %i[child out]], &:read)
    assert_equal "1\n", out
  end
end

class TestLoopControlOutsideLoop < Test::Unit::TestCase
  def test_break_zero_outside_a_loop_only_warns
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'break 0; echo $?; for i in 1; do break 0; echo $?; done', err: err_w], &:read)
    err_w.close
    assert_equal "0\n1\n", out
    assert_equal "rubish: break: only meaningful in a `for', `while', or `until' loop\nrubish: break: 0: loop count out of range\n", err_r.read
  ensure
    err_r&.close
  end
end
