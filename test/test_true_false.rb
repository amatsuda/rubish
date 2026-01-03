# frozen_string_literal: true

require_relative 'test_helper'

class TestTrueFalse < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_truefalse_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test true builtin
  def test_true_returns_true
    result = Rubish::Builtins.run('true', [])
    assert result
  end

  def test_true_with_args_returns_true
    # true ignores all arguments
    result = Rubish::Builtins.run('true', ['ignored', 'args'])
    assert result
  end

  def test_true_is_builtin
    assert Rubish::Builtins.builtin?('true')
  end

  # Test false builtin
  def test_false_returns_false
    result = Rubish::Builtins.run('false', [])
    assert_false result
  end

  def test_false_with_args_returns_false
    # false ignores all arguments
    result = Rubish::Builtins.run('false', ['ignored', 'args'])
    assert_false result
  end

  def test_false_is_builtin
    assert Rubish::Builtins.builtin?('false')
  end

  # Test via REPL with conditionals
  def test_true_in_if_statement
    file = File.join(@tempdir, 'output.txt')
    execute("if true; then echo yes > #{file}; fi")
    assert_equal "yes\n", File.read(file)
  end

  def test_false_in_if_statement
    file = File.join(@tempdir, 'output.txt')
    execute("if false; then echo yes > #{file}; else echo no > #{file}; fi")
    assert_equal "no\n", File.read(file)
  end

  # Test with && and ||
  def test_true_with_and
    file = File.join(@tempdir, 'output.txt')
    execute("true && echo success > #{file}")
    assert_equal "success\n", File.read(file)
  end

  def test_false_with_and
    file = File.join(@tempdir, 'output.txt')
    File.write(file, 'original')
    execute("false && echo success > #{file}")
    assert_equal 'original', File.read(file)
  end

  def test_true_with_or
    file = File.join(@tempdir, 'output.txt')
    File.write(file, 'original')
    execute("true || echo fallback > #{file}")
    assert_equal 'original', File.read(file)
  end

  def test_false_with_or
    file = File.join(@tempdir, 'output.txt')
    execute("false || echo fallback > #{file}")
    assert_equal "fallback\n", File.read(file)
  end

  # Test type identification
  def test_type_identifies_true_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['true']) }
    assert_match(/true is a shell builtin/, output)
  end

  def test_type_identifies_false_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['false']) }
    assert_match(/false is a shell builtin/, output)
  end
end
