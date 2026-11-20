# frozen_string_literal: true

require_relative 'test_helper'

# ${#@}, ${#*}, ${#} count positional parameters; $FUNCNAME is the current function
class TestPositionalCountAndFuncname < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('unset -f f g') rescue nil
  end

  def test_braced_count_forms_with_no_parameters
    out = capture_stdout { execute('echo "${#@}" "${#*}" "${#}"') }
    assert_equal "0 0 0\n", out
  end

  def test_braced_count_forms_with_parameters
    out = capture_stdout { execute('set -- a "b c" d; echo "${#@}" "${#*}" "${#}" $#') }
    assert_equal "3 3 3 3\n", out
  end

  def test_braced_count_inside_function
    execute('f() { echo "${#@}"; }')
    out = capture_stdout { execute('f x y') }
    assert_equal "2\n", out
  end

  def test_funcname_scalar_is_current_function
    execute('f() { echo "$FUNCNAME"; }')
    out = capture_stdout { execute('f') }
    assert_equal "f\n", out
  end

  def test_funcname_scalar_in_nested_call_is_innermost
    execute('g() { echo "$FUNCNAME ${FUNCNAME[1]}"; }; f() { g; }')
    out = capture_stdout { execute('f') }
    assert_equal "g f\n", out
  end

  def test_funcname_outside_function_is_empty
    out = capture_stdout { execute('echo "[$FUNCNAME]"') }
    assert_equal "[]\n", out
  end
end
