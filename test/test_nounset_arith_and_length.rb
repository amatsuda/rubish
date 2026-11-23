# frozen_string_literal: true

require_relative 'test_helper'

# set -u also catches an unset variable inside $(( )), in ${#var}, and an
# unset positional parameter
class TestNounsetArithAndLength < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read, $?.exitstatus]
  ensure
    err_r&.close
  end

  def test_unset_variable_in_arithmetic
    out, err, status = run_shell('set -u; echo $(( u + 1 )); echo not')
    assert_equal '', out
    assert_match(/u: unbound variable/, err)
    assert_not_equal 0, status
  end

  def test_length_of_an_unset_variable
    out, err, = run_shell('set -u; echo ${#u}; echo not')
    assert_equal '', out
    assert_match(/u: unbound variable/, err)
  end

  def test_unset_positional_parameter
    out, err, = run_shell('set -u; set --; echo $1; echo not')
    assert_equal '', out
    assert_match(/\$1: unbound variable/, err)
  end

  def test_set_positional_parameter_is_fine
    out, _err, status = run_shell('set -u; set -- a; echo $1 $(( $# + 1 ))')
    assert_equal "a 2\n", out
    assert_equal 0, status
  end
end
