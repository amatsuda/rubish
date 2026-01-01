# frozen_string_literal: true

require_relative 'test_helper'

class TestRead < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_stdin = $stdin
    @original_env = ENV.to_h
  end

  def teardown
    $stdin = @original_stdin
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def with_stdin(input)
    $stdin = StringIO.new(input)
    yield
  ensure
    $stdin = @original_stdin
  end

  def test_read_is_builtin
    assert Rubish::Builtins.builtin?('read')
  end

  def test_read_single_variable
    with_stdin("hello\n") do
      Rubish::Builtins.run('read', ['VAR'])
    end
    assert_equal 'hello', ENV['VAR']
  end

  def test_read_default_reply
    with_stdin("test input\n") do
      Rubish::Builtins.run('read', [])
    end
    assert_equal 'test input', ENV['REPLY']
  end

  def test_read_multiple_variables
    with_stdin("one two three\n") do
      Rubish::Builtins.run('read', %w[A B C])
    end
    assert_equal 'one', ENV['A']
    assert_equal 'two', ENV['B']
    assert_equal 'three', ENV['C']
  end

  def test_read_last_variable_gets_rest
    with_stdin("one two three four five\n") do
      Rubish::Builtins.run('read', %w[FIRST REST])
    end
    assert_equal 'one', ENV['FIRST']
    assert_equal 'two three four five', ENV['REST']
  end

  def test_read_more_variables_than_words
    with_stdin("only\n") do
      Rubish::Builtins.run('read', %w[A B C])
    end
    assert_equal 'only', ENV['A']
    assert_equal '', ENV['B']
    assert_equal '', ENV['C']
  end

  def test_read_with_prompt
    output = capture_output do
      with_stdin("answer\n") do
        Rubish::Builtins.run('read', ['-p', 'Enter value: ', 'VAR'])
      end
    end
    assert_equal 'Enter value: ', output
    assert_equal 'answer', ENV['VAR']
  end

  def test_read_prompt_with_multiple_vars
    with_stdin("foo bar\n") do
      Rubish::Builtins.run('read', ['-p', 'Input: ', 'X', 'Y'])
    end
    assert_equal 'foo', ENV['X']
    assert_equal 'bar', ENV['Y']
  end

  def test_read_empty_line
    with_stdin("\n") do
      Rubish::Builtins.run('read', ['VAR'])
    end
    assert_equal '', ENV['VAR']
  end

  def test_read_returns_false_on_eof
    with_stdin('') do
      result = Rubish::Builtins.run('read', ['VAR'])
      assert_equal false, result
    end
  end

  def test_read_returns_true_on_success
    with_stdin("data\n") do
      result = Rubish::Builtins.run('read', ['VAR'])
      assert_equal true, result
    end
  end

  def test_read_strips_newline
    with_stdin("no newline in value\n") do
      Rubish::Builtins.run('read', ['VAR'])
    end
    assert_equal 'no newline in value', ENV['VAR']
    assert_no_match(/\n/, ENV['VAR'])
  end

  private

  def capture_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
