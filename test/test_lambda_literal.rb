# frozen_string_literal: true

require_relative 'test_helper'

class TestLambdaLiteral < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  # ==========================================================================
  # Lambda literal evaluation (-> { ... }) - auto-called if no required args
  # ==========================================================================

  def test_simple_lambda_auto_called
    out = capture_stdout { execute('-> { 1 + 2 }') }
    assert_equal "3\n", out
  end

  def test_lambda_with_required_args_not_called
    out = capture_stdout { execute('->(x) { x * 2 }') }
    assert_match(/#<Proc:.*\(lambda\)>/, out)
  end

  def test_lambda_with_multiple_required_args_not_called
    out = capture_stdout { execute('->(x, y) { x + y }') }
    assert_match(/#<Proc:.*\(lambda\)>/, out)
  end

  def test_lambda_explicit_call
    out = capture_stdout { execute('->(x) { x * 3 }.call(7)') }
    assert_equal "21\n", out
  end

  def test_lambda_with_string
    out = capture_stdout { execute('-> { "hello" }') }
    assert_equal "\"hello\"\n", out
  end

  def test_lambda_with_array
    out = capture_stdout { execute('-> { [1, 2, 3] }') }
    assert_equal "[1, 2, 3]\n", out
  end

  # ==========================================================================
  # Error handling
  # ==========================================================================

  def test_lambda_syntax_error
    err = capture_stderr { execute('-> { 1 +') }
    assert_match(/syntax error|unexpected/i, err)
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_lambda_incomplete
    err = capture_stderr { execute('->') }
    assert_match(/syntax error|unexpected/i, err)
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_lambda_runtime_error
    err = capture_stderr { execute('-> { undefined_var }') }
    assert_match(/undefined/, err)
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end
end
