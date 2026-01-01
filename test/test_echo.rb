# frozen_string_literal: true

require_relative 'test_helper'

class TestEcho < Test::Unit::TestCase
  def test_echo_is_builtin
    assert Rubish::Builtins.builtin?('echo')
  end

  def test_echo_simple
    output = capture_output { Rubish::Builtins.run('echo', ['hello']) }
    assert_equal "hello\n", output
  end

  def test_echo_multiple_args
    output = capture_output { Rubish::Builtins.run('echo', %w[hello world]) }
    assert_equal "hello world\n", output
  end

  def test_echo_no_args
    output = capture_output { Rubish::Builtins.run('echo', []) }
    assert_equal "\n", output
  end

  def test_echo_n_flag
    output = capture_output { Rubish::Builtins.run('echo', ['-n', 'no newline']) }
    assert_equal 'no newline', output
  end

  def test_echo_n_flag_multiple_args
    output = capture_output { Rubish::Builtins.run('echo', ['-n', 'one', 'two', 'three']) }
    assert_equal 'one two three', output
  end

  def test_echo_n_flag_no_args
    output = capture_output { Rubish::Builtins.run('echo', ['-n']) }
    assert_equal '', output
  end

  def test_echo_returns_true
    capture_output { assert_equal true, Rubish::Builtins.run('echo', ['test']) }
  end

  def test_echo_preserves_spaces_between_args
    output = capture_output { Rubish::Builtins.run('echo', %w[a b c]) }
    assert_equal "a b c\n", output
  end
end
