# frozen_string_literal: true

require_relative 'test_helper'

# Unit tests for the shell arithmetic evaluator (no Ruby eval involved)
class TestArithmeticEvaluator < Test::Unit::TestCase
  def setup
    @vars = {}
    @arrays = Hash.new { |h, k| h[k] = {} }
    @positional = %w[p1 p2]
    @substituted = []
    @evaluator = Rubish::ArithmeticEvaluator.new(
      get_var: ->(name) { @vars[name] },
      set_var: ->(name, value) { @vars[name] = value },
      get_array_element: ->(name, idx) { @arrays[name][idx] },
      set_array_element: ->(name, idx, value) { @arrays[name][idx] = value },
      positional: ->(n) { @positional[n - 1] },
      var_set: ->(name) { @vars.key?(name) },
      subst: ->(cmd) { @substituted << cmd; '2' }
    )
  end

  def ev(expr)
    @evaluator.evaluate(expr)
  end

  # --- literals ---
  def test_decimal_hex_octal_and_base_literals
    assert_equal 42, ev('42')
    assert_equal 255, ev('0xff')
    assert_equal 31, ev('0X1F')
    assert_equal 8, ev('010')
    assert_equal 5, ev('2#101')
    assert_equal 255, ev('16#ff')
    assert_equal 15, ev('8#17')
    assert_equal 15, ev('10#15')
  end

  def test_float_literals_evaluate_as_floats
    assert_equal 2.5, ev('1.5 + 1')
    assert_equal 3, ev('int(3.7)')
  end

  def test_empty_expression_is_zero
    assert_equal 0, ev('')
    assert_equal 0, ev('   ')
  end

  # --- operators and precedence ---
  def test_precedence_and_parentheses
    assert_equal 14, ev('2 + 3 * 4')
    assert_equal 20, ev('(2 + 3) * 4')
    assert_equal 512, ev('2 ** 3 ** 2')
    assert_equal 4, ev('-2 ** 2')
  end

  def test_division_truncates_toward_zero_like_c
    assert_equal(-3, ev('7 / -2'))
    assert_equal(-3, ev('-7 / 2'))
    assert_equal 3, ev('7 / 2')
  end

  def test_modulo_takes_sign_of_dividend_like_c
    assert_equal(-1, ev('-7 % 3'))
    assert_equal 1, ev('7 % -3')
    assert_equal 2, ev('17 % 5')
  end

  def test_bitwise_and_shift_operators
    assert_equal 8, ev('1 << 3')
    assert_equal(-1, ev('-1 >> 1'))
    assert_equal 1, ev('5 & 3')
    assert_equal 7, ev('5 | 3')
    assert_equal 6, ev('5 ^ 3')
    assert_equal(-6, ev('~5'))
  end

  def test_logical_not_and_comparisons_yield_zero_or_one
    assert_equal 1, ev('!0')
    assert_equal 0, ev('!5')
    assert_equal 1, ev('3 < 5')
    assert_equal 0, ev('3 > 5')
    assert_equal 1, ev('5 >= 5')
    assert_equal 1, ev('5 <= 5')
    assert_equal 1, ev('5 == 5')
    assert_equal 1, ev('5 != 4')
  end

  def test_logical_operators_short_circuit
    assert_equal 0, ev('0 && (x = 5)')
    assert_nil @vars['x']
    assert_equal 1, ev('1 || (x = 5)')
    assert_nil @vars['x']
    assert_equal 1, ev('0 || (x = 5)')
    assert_equal '5', @vars['x']
  end

  def test_ternary_operator
    assert_equal 3, ev('0 ? 2 : 3')
    assert_equal 2, ev('1 ? 2 : 3')
    assert_equal 30, ev('0 ? 10 : 0 ? 20 : 30')
  end

  def test_comma_evaluates_all_and_returns_last
    assert_equal 3, ev('x = 1, y = 2, 3')
    assert_equal '1', @vars['x']
    assert_equal '2', @vars['y']
  end

  # --- assignment, increment ---
  def test_assignment_sets_variable_and_returns_value
    assert_equal 5, ev('x = 5')
    assert_equal '5', @vars['x']
    assert_equal 7, ev('x += 2')
    assert_equal 14, ev('x <<= 1')
    assert_equal 4, ev('x %= 10')
    assert_equal 16, ev('x **= 2')
  end

  def test_increment_and_decrement
    @vars['n'] = '5'
    assert_equal 6, ev('++n')
    assert_equal 6, ev('n++')
    assert_equal '7', @vars['n']
    assert_equal 6, ev('--n')
    assert_equal 6, ev('n--')
    assert_equal '5', @vars['n']
  end

  # --- variables ---
  def test_unset_variable_is_zero
    assert_equal 5, ev('nope + 5')
  end

  def test_variable_forms
    @vars['x'] = '4'
    assert_equal 4, ev('x')
    assert_equal 4, ev('$x')
    assert_equal 4, ev('${x}')
    assert_equal 1, ev('${+x}')
    assert_equal 0, ev('${+nope}')
    assert_equal 1, ev('${#x}')
  end

  def test_variable_value_is_evaluated_recursively
    @vars['x'] = '1 + 2'
    @vars['y'] = 'x * 2'
    assert_equal 3, ev('x')
    assert_equal 6, ev('y')
  end

  def test_self_referential_variable_is_an_error_not_a_hang
    @vars['x'] = 'x + 1'
    assert_raise(Rubish::ArithmeticEvaluator::Error) { ev('x') }
  end

  def test_positional_parameters
    @positional = %w[7 8]
    assert_equal 15, ev('$1 + $2')
  end

  def test_array_elements
    @arrays['a'][1] = '10'
    @arrays['a'][2] = '20'
    @vars['i'] = '2'
    assert_equal 30, ev('a[1] + ${a[i]}')
    assert_equal 7, ev('a[3] = 7')
    assert_equal '7', @arrays['a'][3]
    assert_equal 11, ev('a[1] += 1')
  end

  def test_command_substitution_uses_callback
    assert_equal 5, ev('$(echo 2) + 3')
    assert_equal ['echo 2'], @substituted
  end

  # --- functions ---
  def test_math_functions
    assert_equal 3, ev('abs(-3)')
    assert_equal 4.0, ev('sqrt(16)')
    assert_equal 2, ev('rint(2.4)')
    assert_equal 3, ev('int(rint(2.6))')
    assert_equal 2, ev('floor(2.9)')
    assert_equal 3, ev('ceil(2.1)')
  end

  def test_unknown_function_is_an_error
    assert_raise(Rubish::ArithmeticEvaluator::Error) { ev('system("echo pwned")') }
  end

  # --- errors (and no code execution) ---
  def test_division_by_zero_is_an_error
    err = assert_raise(Rubish::ArithmeticEvaluator::Error) { ev('1 / 0') }
    assert_match(/division by 0/, err.message)
    assert_raise(Rubish::ArithmeticEvaluator::Error) { ev('1 % 0') }
  end

  def test_syntax_errors_are_reported_not_swallowed
    err = assert_raise(Rubish::ArithmeticEvaluator::Error) { ev('3 +') }
    assert_match(/syntax error/, err.message)
    assert_raise(Rubish::ArithmeticEvaluator::Error) { ev('08') }
    assert_raise(Rubish::ArithmeticEvaluator::Error) { ev('(1 + 2') }
    assert_raise(Rubish::ArithmeticEvaluator::Error) { ev("'a'") }
  end

  def test_ruby_code_in_variable_value_is_never_executed
    marker = File.join(Dir.tmpdir, "rubish_arith_pwned_#{$$}")
    @vars['x'] = %(system("touch #{marker}"))
    @vars['y'] = "`touch #{marker}`"
    @vars['z'] = 'Kernel.exit(42)'
    %w[x y z].each do |name|
      assert_raise(Rubish::ArithmeticEvaluator::Error) { ev(name) }
    end
    assert_false File.exist?(marker)
  end

  def test_negative_exponent_is_an_error
    assert_raise(Rubish::ArithmeticEvaluator::Error) { ev('2 ** -1') }
  end

  # --- 64-bit integer semantics ---
  def test_integers_wrap_at_64_bits
    assert_equal 0, ev('2 ** 62 * 4')
    assert_equal(-9_223_372_036_854_775_808, ev('9223372036854775807 + 1'))
  end
end
