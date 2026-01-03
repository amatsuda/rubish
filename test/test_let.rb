# frozen_string_literal: true

require_relative 'test_helper'

class TestLet < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_let_test')
    Rubish::Builtins.clear_readonly_vars
  end

  def teardown
    Rubish::Builtins.clear_readonly_vars
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test simple assignment
  def test_let_simple_assignment
    Rubish::Builtins.run('let', ['a=5'])
    assert_equal '5', ENV['a']
  end

  def test_let_arithmetic_assignment
    Rubish::Builtins.run('let', ['a=5+3'])
    assert_equal '8', ENV['a']
  end

  def test_let_complex_expression
    Rubish::Builtins.run('let', ['a=2*3+4'])
    assert_equal '10', ENV['a']
  end

  def test_let_with_parentheses
    Rubish::Builtins.run('let', ['a=(2+3)*4'])
    assert_equal '20', ENV['a']
  end

  # Test variable references
  def test_let_with_variable
    ENV['x'] = '10'
    Rubish::Builtins.run('let', ['a=x+5'])
    assert_equal '15', ENV['a']
  end

  def test_let_with_dollar_variable
    ENV['x'] = '10'
    Rubish::Builtins.run('let', ['a=$x+5'])
    assert_equal '15', ENV['a']
  end

  def test_let_with_braced_variable
    ENV['x'] = '10'
    Rubish::Builtins.run('let', ['a=${x}+5'])
    assert_equal '15', ENV['a']
  end

  # Test compound assignment operators
  def test_let_plus_equals
    ENV['a'] = '10'
    Rubish::Builtins.run('let', ['a+=5'])
    assert_equal '15', ENV['a']
  end

  def test_let_minus_equals
    ENV['a'] = '10'
    Rubish::Builtins.run('let', ['a-=3'])
    assert_equal '7', ENV['a']
  end

  def test_let_multiply_equals
    ENV['a'] = '10'
    Rubish::Builtins.run('let', ['a*=2'])
    assert_equal '20', ENV['a']
  end

  def test_let_divide_equals
    ENV['a'] = '10'
    Rubish::Builtins.run('let', ['a/=2'])
    assert_equal '5', ENV['a']
  end

  def test_let_modulo_equals
    ENV['a'] = '10'
    Rubish::Builtins.run('let', ['a%=3'])
    assert_equal '1', ENV['a']
  end

  # Test increment/decrement operators
  def test_let_pre_increment
    ENV['a'] = '5'
    result = Rubish::Builtins.run('let', ['++a'])
    assert_equal '6', ENV['a']
    assert result  # Returns true because 6 != 0
  end

  def test_let_pre_decrement
    ENV['a'] = '5'
    Rubish::Builtins.run('let', ['--a'])
    assert_equal '4', ENV['a']
  end

  def test_let_post_increment
    ENV['a'] = '5'
    Rubish::Builtins.run('let', ['a++'])
    assert_equal '6', ENV['a']
  end

  def test_let_post_decrement
    ENV['a'] = '5'
    Rubish::Builtins.run('let', ['a--'])
    assert_equal '4', ENV['a']
  end

  # Test multiple expressions
  def test_let_multiple_expressions
    Rubish::Builtins.run('let', ['a=5', 'b=10', 'c=a+b'])
    assert_equal '5', ENV['a']
    assert_equal '10', ENV['b']
    assert_equal '15', ENV['c']
  end

  # Test return value
  def test_let_returns_true_for_nonzero
    result = Rubish::Builtins.run('let', ['a=5'])
    assert result  # 5 != 0
  end

  def test_let_returns_false_for_zero
    result = Rubish::Builtins.run('let', ['a=0'])
    assert_false result  # 0 == 0
  end

  def test_let_returns_based_on_last_expression
    result = Rubish::Builtins.run('let', ['a=5', 'b=0'])
    assert_false result  # last expression is 0
  end

  # Test comparison operators
  def test_let_comparison_equal
    ENV['a'] = '5'
    result = Rubish::Builtins.run('let', ['a==5'])
    assert result
  end

  def test_let_comparison_not_equal
    ENV['a'] = '5'
    result = Rubish::Builtins.run('let', ['a!=3'])
    assert result
  end

  def test_let_comparison_less_than
    ENV['a'] = '3'
    result = Rubish::Builtins.run('let', ['a<5'])
    assert result
  end

  def test_let_comparison_greater_than
    ENV['a'] = '10'
    result = Rubish::Builtins.run('let', ['a>5'])
    assert result
  end

  # Test logical operators
  def test_let_logical_and
    ENV['a'] = '5'
    ENV['b'] = '10'
    result = Rubish::Builtins.run('let', ['a>0&&b>0'])
    assert result
  end

  def test_let_logical_or
    ENV['a'] = '0'
    ENV['b'] = '10'
    result = Rubish::Builtins.run('let', ['a>0||b>0'])
    assert result
  end

  # Test readonly protection
  def test_let_readonly_protected
    Rubish::Builtins.run('readonly', ['CONST=5'])
    output = capture_output do
      Rubish::Builtins.run('let', ['CONST=10'])
    end
    assert_match(/readonly/, output)
    assert_equal '5', ENV['CONST']
  end

  # Test via REPL
  def test_let_via_repl
    execute('let a=5+5')
    assert_equal '10', ENV['a']
  end

  def test_let_increment_via_repl
    ENV['counter'] = '0'
    execute('let counter++')
    assert_equal '1', ENV['counter']
  end

  # Test uninitialized variable
  def test_let_uninitialized_var
    ENV.delete('x')
    Rubish::Builtins.run('let', ['a=x+5'])
    assert_equal '5', ENV['a']  # x defaults to 0
  end

  # Test usage error
  def test_let_no_args
    output = capture_output { Rubish::Builtins.run('let', []) }
    assert_match(/usage/, output)
  end

  # Test division by zero
  def test_let_division_by_zero
    ENV['a'] = '10'
    Rubish::Builtins.run('let', ['a/=0'])
    assert_equal '0', ENV['a']  # Protected from crash
  end
end
