# frozen_string_literal: true

require_relative 'test_helper'

# Shell-level arithmetic: bash semantics, error reporting, and no Ruby eval
class TestArithmeticSafety < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
  end

  def teardown
    Rubish::Builtins.unset(%w[x n])
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  def test_ruby_code_in_variable_is_not_executed_by_arithmetic_expansion
    marker = File.join(Dir.tmpdir, "rubish_arith_shell_pwned_#{$$}")
    execute(%(x='system("touch #{marker}")'))
    capture_output { execute('echo $(( x ))') }
    assert_false File.exist?(marker)
  end

  def test_ruby_code_in_variable_does_not_exit_the_shell
    execute("x='Kernel.exit(42)'")
    out = capture_output { catch(:exit) { execute('echo $(( x )); echo alive') } }
    assert_match(/alive/, out)
  end

  def test_declare_i_does_not_eval_ruby
    marker = File.join(Dir.tmpdir, "rubish_arith_declare_pwned_#{$$}")
    execute('declare -i n')
    capture_output { execute(%(n='system("touch #{marker}")')) }
    assert_false File.exist?(marker)
  end

  def test_let_does_not_eval_ruby
    marker = File.join(Dir.tmpdir, "rubish_arith_let_pwned_#{$$}")
    capture_output { execute(%(let 'x = system("touch #{marker}")')) }
    assert_false File.exist?(marker)
  end

  def test_c_style_division_and_modulo
    out = capture_stdout { execute('echo $(( 7 / -2 )) $(( -7 % 3 )) $(( 7 % -3 ))') }
    assert_equal "-3 -1 1\n", out
  end

  def test_base_notation
    out = capture_stdout { execute('echo $(( 10#15 )) $(( 16#ff )) $(( 2#101 ))') }
    assert_equal "15 255 5\n", out
  end

  def test_ternary_with_false_condition
    out = capture_stdout { execute('echo $(( 0 ? 2 : 3 ))') }
    assert_equal "3\n", out
  end

  def test_command_substitution_inside_arithmetic
    out = capture_stdout { execute('echo $(( $(echo 2) + 3 ))') }
    assert_equal "5\n", out
  end

  def test_sixty_four_bit_wraparound
    out = capture_stdout { execute('echo $(( 2 ** 62 * 4 ))') }
    assert_equal "0\n", out
  end

  def test_division_by_zero_reports_error_and_fails
    out = capture_output { execute('echo $(( 1 / 0 )); echo after') }
    assert_match(/division by 0/, out)
    assert_match(/after/, out)
    assert_no_match(/^0$/, out)
  end

  def test_division_by_zero_in_arithmetic_command_fails_with_status_1
    capture_output { execute('(( 1 / 0 ))') }
    assert_equal 1, last_status
  end

  def test_syntax_error_reports_error
    out = capture_output { execute('echo $(( 3 + ))') }
    assert_match(/syntax error/, out)
    assert_equal 1, last_status
  end

  def test_let_with_shell_variable_and_status
    execute('x=5')
    out = capture_stdout { execute('let "n = x * 2"; echo $n') }
    assert_equal "10\n", out
  end

  def test_declare_i_evaluates_expression_with_shell_variables
    execute('x=5; declare -i n; n="x + 1"')
    out = capture_stdout { execute('echo $n') }
    assert_equal "6\n", out
  end

  def test_float_math_functions_still_work
    out = capture_stdout { execute('echo $(( int(rint(1.5 * 1000)) ))') }
    assert_equal "1500\n", out
  end
end
