# frozen_string_literal: true

require_relative 'test_helper'

class TestArithmetic < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_arith_test')
    @saved_env = ENV.to_h
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @saved_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Basic operations
  def test_addition
    execute("echo $((1 + 2)) > #{output_file}")
    assert_equal "3\n", File.read(output_file)
  end

  def test_subtraction
    execute("echo $((10 - 3)) > #{output_file}")
    assert_equal "7\n", File.read(output_file)
  end

  def test_multiplication
    execute("echo $((4 * 5)) > #{output_file}")
    assert_equal "20\n", File.read(output_file)
  end

  def test_division
    execute("echo $((20 / 4)) > #{output_file}")
    assert_equal "5\n", File.read(output_file)
  end

  def test_modulo
    execute("echo $((17 % 5)) > #{output_file}")
    assert_equal "2\n", File.read(output_file)
  end

  def test_exponentiation
    execute("echo $((2 ** 8)) > #{output_file}")
    assert_equal "256\n", File.read(output_file)
  end

  # Operator precedence
  def test_precedence
    execute("echo $((2 + 3 * 4)) > #{output_file}")
    assert_equal "14\n", File.read(output_file)
  end

  def test_parentheses
    execute("echo $(((2 + 3) * 4)) > #{output_file}")
    assert_equal "20\n", File.read(output_file)
  end

  # Variables
  def test_variable_plain
    ENV['X'] = '10'
    execute("echo $((X + 5)) > #{output_file}")
    assert_equal "15\n", File.read(output_file)
  end

  def test_variable_dollar
    ENV['Y'] = '7'
    execute("echo $(($Y * 3)) > #{output_file}")
    assert_equal "21\n", File.read(output_file)
  end

  def test_variable_braces
    ENV['Z'] = '8'
    execute("echo $((${Z} + 2)) > #{output_file}")
    assert_equal "10\n", File.read(output_file)
  end

  def test_unset_variable_defaults_to_zero
    ENV.delete('UNSET')
    execute("echo $((UNSET + 5)) > #{output_file}")
    assert_equal "5\n", File.read(output_file)
  end

  # Negative numbers
  def test_negative_result
    execute("echo $((5 - 10)) > #{output_file}")
    assert_equal "-5\n", File.read(output_file)
  end

  def test_negative_operand
    execute("echo $((-5 + 10)) > #{output_file}")
    assert_equal "5\n", File.read(output_file)
  end

  # Complex expressions
  def test_complex_expression
    ENV['A'] = '2'
    ENV['B'] = '3'
    execute("echo $((A * B + A ** B)) > #{output_file}")
    assert_equal "14\n", File.read(output_file)
  end

  # Multiple arithmetic expansions
  def test_multiple_expansions
    execute("echo $((1+1)) $((2+2)) $((3+3)) > #{output_file}")
    assert_equal "2 4 6\n", File.read(output_file)
  end

  # Mixed with text
  def test_mixed_with_text
    execute("echo result: $((10 * 10)) > #{output_file}")
    assert_equal "result: 100\n", File.read(output_file)
  end

  # Bitwise operations (Ruby supports these)
  def test_bitwise_and
    execute("echo $((12 & 10)) > #{output_file}")
    assert_equal "8\n", File.read(output_file)
  end

  def test_bitwise_or
    execute("echo $((12 | 10)) > #{output_file}")
    assert_equal "14\n", File.read(output_file)
  end

  def test_bitwise_xor
    execute("echo $((12 ^ 10)) > #{output_file}")
    assert_equal "6\n", File.read(output_file)
  end

  def test_left_shift
    execute("echo $((1 << 4)) > #{output_file}")
    assert_equal "16\n", File.read(output_file)
  end

  def test_right_shift
    execute("echo $((16 >> 2)) > #{output_file}")
    assert_equal "4\n", File.read(output_file)
  end

  # Comparison (returns 1 for true, 0 for false)
  def test_comparison_less_than
    execute("echo $((3 < 5 ? 1 : 0)) > #{output_file}")
    assert_equal "1\n", File.read(output_file)
  end

  def test_comparison_greater_than
    execute("echo $((5 > 3 ? 1 : 0)) > #{output_file}")
    assert_equal "1\n", File.read(output_file)
  end

  # In variable assignment
  def test_in_assignment
    execute('export X=$((5 + 5))')
    execute("echo $X > #{output_file}")
    assert_equal "10\n", File.read(output_file)
  end
end
