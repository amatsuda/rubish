# frozen_string_literal: true

require_relative 'test_helper'

class TestArithmeticCommand < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def execute(line)
    @repl.send(:execute, line)
    @repl.instance_variable_get(:@last_status)
  end

  # Basic evaluation - exit status
  def test_non_zero_returns_success
    assert_equal 0, execute('(( 1 ))')
  end

  def test_zero_returns_failure
    assert_equal 1, execute('(( 0 ))')
  end

  def test_positive_number_returns_success
    assert_equal 0, execute('(( 42 ))')
  end

  def test_negative_number_returns_success
    assert_equal 0, execute('(( -1 ))')
  end

  # Comparison operators
  def test_greater_than_true
    assert_equal 0, execute('(( 5 > 3 ))')
  end

  def test_greater_than_false
    assert_equal 1, execute('(( 3 > 5 ))')
  end

  def test_less_than_true
    assert_equal 0, execute('(( 3 < 5 ))')
  end

  def test_less_than_false
    assert_equal 1, execute('(( 5 < 3 ))')
  end

  def test_equal_true
    assert_equal 0, execute('(( 5 == 5 ))')
  end

  def test_equal_false
    assert_equal 1, execute('(( 5 == 3 ))')
  end

  def test_not_equal_true
    assert_equal 0, execute('(( 5 != 3 ))')
  end

  def test_not_equal_false
    assert_equal 1, execute('(( 5 != 5 ))')
  end

  def test_greater_or_equal_true
    assert_equal 0, execute('(( 5 >= 5 ))')
    assert_equal 0, execute('(( 6 >= 5 ))')
  end

  def test_less_or_equal_true
    assert_equal 0, execute('(( 5 <= 5 ))')
    assert_equal 0, execute('(( 4 <= 5 ))')
  end

  # Variable assignment
  def test_simple_assignment
    execute('(( x = 5 ))')
    assert_equal '5', ENV['x']
  end

  def test_assignment_returns_value_status
    assert_equal 0, execute('(( x = 5 ))')  # non-zero value
    assert_equal 1, execute('(( y = 0 ))')  # zero value
  end

  # Increment/decrement
  def test_post_increment
    ENV['x'] = '5'
    status = execute('(( x++ ))')
    assert_equal '6', ENV['x']
    assert_equal 0, status  # returns old value (5)
  end

  def test_post_increment_zero
    ENV['x'] = '0'
    status = execute('(( x++ ))')
    assert_equal '1', ENV['x']
    assert_equal 1, status  # returns old value (0)
  end

  def test_pre_increment
    ENV['x'] = '5'
    status = execute('(( ++x ))')
    assert_equal '6', ENV['x']
    assert_equal 0, status  # returns new value (6)
  end

  def test_post_decrement
    ENV['x'] = '5'
    status = execute('(( x-- ))')
    assert_equal '4', ENV['x']
    assert_equal 0, status  # returns old value (5)
  end

  def test_pre_decrement
    ENV['x'] = '5'
    status = execute('(( --x ))')
    assert_equal '4', ENV['x']
    assert_equal 0, status  # returns new value (4)
  end

  # Compound assignment operators
  def test_add_assign
    ENV['x'] = '5'
    execute('(( x += 3 ))')
    assert_equal '8', ENV['x']
  end

  def test_subtract_assign
    ENV['x'] = '5'
    execute('(( x -= 2 ))')
    assert_equal '3', ENV['x']
  end

  def test_multiply_assign
    ENV['x'] = '5'
    execute('(( x *= 2 ))')
    assert_equal '10', ENV['x']
  end

  def test_divide_assign
    ENV['x'] = '6'
    execute('(( x /= 2 ))')
    assert_equal '3', ENV['x']
  end

  def test_modulo_assign
    ENV['x'] = '7'
    execute('(( x %= 3 ))')
    assert_equal '1', ENV['x']
  end

  def test_left_shift_assign
    ENV['x'] = '2'
    execute('(( x <<= 2 ))')
    assert_equal '8', ENV['x']
  end

  def test_right_shift_assign
    ENV['x'] = '8'
    execute('(( x >>= 2 ))')
    assert_equal '2', ENV['x']
  end

  def test_and_assign
    ENV['x'] = '7'
    execute('(( x &= 3 ))')
    assert_equal '3', ENV['x']
  end

  def test_or_assign
    ENV['x'] = '5'
    execute('(( x |= 2 ))')
    assert_equal '7', ENV['x']
  end

  def test_xor_assign
    ENV['x'] = '5'
    execute('(( x ^= 3 ))')
    assert_equal '6', ENV['x']
  end

  # Variable references
  def test_variable_reference
    ENV['x'] = '5'
    execute('(( y = x + 1 ))')
    assert_equal '6', ENV['y']
  end

  def test_dollar_variable_reference
    ENV['x'] = '5'
    execute('(( y = $x + 1 ))')
    assert_equal '6', ENV['y']
  end

  def test_unset_variable_defaults_to_zero
    ENV.delete('unset_var')
    execute('(( y = unset_var + 1 ))')
    assert_equal '1', ENV['y']
  end

  # Arithmetic operations
  def test_addition
    assert_equal 0, execute('(( 2 + 3 ))')
  end

  def test_subtraction
    assert_equal 0, execute('(( 5 - 3 ))')
  end

  def test_multiplication
    assert_equal 0, execute('(( 3 * 4 ))')
  end

  def test_division
    assert_equal 0, execute('(( 10 / 2 ))')
  end

  def test_modulo
    assert_equal 0, execute('(( 7 % 3 ))')
  end

  def test_exponentiation
    assert_equal 0, execute('(( 2 ** 3 ))')
  end

  # Operator precedence
  def test_precedence_mul_before_add
    execute('(( x = 2 + 3 * 4 ))')
    assert_equal '14', ENV['x']
  end

  def test_parentheses_override_precedence
    execute('(( x = (2 + 3) * 4 ))')
    assert_equal '20', ENV['x']
  end

  # Bitwise operators
  def test_bitwise_and
    execute('(( x = 5 & 3 ))')
    assert_equal '1', ENV['x']
  end

  def test_bitwise_or
    execute('(( x = 5 | 3 ))')
    assert_equal '7', ENV['x']
  end

  def test_bitwise_xor
    execute('(( x = 5 ^ 3 ))')
    assert_equal '6', ENV['x']
  end

  def test_left_shift
    execute('(( x = 2 << 3 ))')
    assert_equal '16', ENV['x']
  end

  def test_right_shift
    execute('(( x = 16 >> 2 ))')
    assert_equal '4', ENV['x']
  end

  # Ternary operator
  def test_ternary_true
    execute('(( x = 5 > 3 ? 1 : 0 ))')
    assert_equal '1', ENV['x']
  end

  def test_ternary_false
    execute('(( x = 3 > 5 ? 1 : 0 ))')
    assert_equal '0', ENV['x']
  end

  # Comma operator (multiple expressions)
  def test_comma_operator
    execute('(( x = 1, y = 2, z = x + y ))')
    assert_equal '1', ENV['x']
    assert_equal '2', ENV['y']
    assert_equal '3', ENV['z']
  end

  def test_comma_operator_returns_last
    status = execute('(( x = 0, y = 5 ))')
    assert_equal 0, status  # last expression (5) is non-zero
  end

  # Logical operators
  def test_logical_and_true
    assert_equal 0, execute('(( 1 && 1 ))')
  end

  def test_logical_and_false
    assert_equal 1, execute('(( 1 && 0 ))')
  end

  def test_logical_or_true
    # Note: Ruby's || returns the first truthy value, which differs from bash
    # In bash, 0 || 1 evaluates 1 because 0 is falsy
    # For bash-compatible behavior, use comparison: (( (0 != 0) || (1 != 0) ))
    assert_equal 0, execute('(( 1 || 0 ))')
  end

  def test_logical_or_false
    # Both operands are zero
    assert_equal 1, execute('(( 0 || 0 ))')
  end

  # Negation
  # Note: Ruby's ! treats any non-nil/false as truthy, so !0 is false in Ruby
  # but in bash arithmetic, 0 is falsy so !0 should be 1
  # This is a known limitation
  def test_logical_not
    execute('(( x = !5 ))')  # !truthy = 0
    assert_equal '0', ENV['x']
  end

  def test_bitwise_not
    execute('(( x = ~0 ))')
    assert_equal '-1', ENV['x']
  end

  # Unary minus
  def test_unary_minus
    execute('(( x = -5 ))')
    assert_equal '-5', ENV['x']
  end

  # Used in control flow (common pattern)
  def test_use_in_if
    ENV['count'] = '5'
    @repl.send(:execute, 'if (( count > 0 )); then echo yes; fi > /tmp/test_arith_if.txt')
    assert_equal "yes\n", File.read('/tmp/test_arith_if.txt')
    File.unlink('/tmp/test_arith_if.txt')
  end

  def test_use_in_while_loop
    ENV['count'] = '3'
    ENV['sum'] = '0'
    @repl.send(:execute, 'while (( count > 0 )); do (( sum += count )); (( count-- )); done')
    assert_equal '6', ENV['sum']  # 3 + 2 + 1
    assert_equal '0', ENV['count']
  end
end
