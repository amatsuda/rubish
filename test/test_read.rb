# frozen_string_literal: true

require_relative 'test_helper'

class TestRead < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_stdin = $stdin
    @original_stderr = $stderr
    @original_env = ENV.to_h
  end

  def teardown
    $stdin = @original_stdin
    $stderr = @original_stderr
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
    $stderr = StringIO.new
    with_stdin("answer\n") do
      Rubish::Builtins.run('read', ['-p', 'Enter value: ', 'VAR'])
    end
    assert_equal 'Enter value: ', $stderr.string
    assert_equal 'answer', ENV['VAR']
  end

  def test_read_prompt_with_multiple_vars
    $stderr = StringIO.new
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

  # -r raw mode tests
  def test_read_without_raw_processes_escapes
    with_stdin("hello\\tworld\n") do
      Rubish::Builtins.run('read', ['VAR'])
    end
    assert_equal 'hellotworld', ENV['VAR']  # Backslash escapes next char
  end

  def test_read_raw_mode_preserves_backslashes
    with_stdin("hello\\tworld\n") do
      Rubish::Builtins.run('read', ['-r', 'VAR'])
    end
    assert_equal 'hello\\tworld', ENV['VAR']
  end

  def test_read_raw_mode_preserves_trailing_backslash
    with_stdin("hello\\\n") do
      Rubish::Builtins.run('read', ['-r', 'VAR'])
    end
    assert_equal 'hello\\', ENV['VAR']
  end

  def test_read_without_raw_removes_trailing_backslash
    with_stdin("hello\\\n") do
      Rubish::Builtins.run('read', ['VAR'])
    end
    assert_equal 'hello', ENV['VAR']
  end

  # -d delimiter tests
  def test_read_with_delimiter
    with_stdin('hello:world:test') do
      Rubish::Builtins.run('read', ['-d', ':', 'VAR'])
    end
    assert_equal 'hello', ENV['VAR']
  end

  def test_read_with_delimiter_reads_until_first_match
    with_stdin('first|second|third') do
      Rubish::Builtins.run('read', ['-d', '|', 'VAR'])
    end
    assert_equal 'first', ENV['VAR']
  end

  def test_read_with_delimiter_only_uses_first_char
    with_stdin('hello::world') do
      Rubish::Builtins.run('read', ['-d', '::', 'VAR'])
    end
    assert_equal 'hello', ENV['VAR']  # Only first : is used
  end

  # -n nchars tests
  def test_read_nchars
    with_stdin('hello world') do
      Rubish::Builtins.run('read', ['-n', '5', 'VAR'])
    end
    assert_equal 'hello', ENV['VAR']
  end

  def test_read_nchars_stops_at_newline
    with_stdin("hi\nthere") do
      Rubish::Builtins.run('read', ['-n', '10', 'VAR'])
    end
    assert_equal 'hi', ENV['VAR']
  end

  def test_read_nchars_with_less_input
    with_stdin("abc\n") do
      Rubish::Builtins.run('read', ['-n', '10', 'VAR'])
    end
    assert_equal 'abc', ENV['VAR']
  end

  # -N nchars (exact) tests
  def test_read_exact_nchars
    with_stdin("hello\nworld") do
      Rubish::Builtins.run('read', ['-N', '7', 'VAR'])
    end
    assert_equal "hello\nw", ENV['VAR']  # Includes newline
  end

  def test_read_exact_nchars_ignores_delimiter
    with_stdin('ab:cd:ef') do
      Rubish::Builtins.run('read', ['-N', '5', '-d', ':', 'VAR'])
    end
    assert_equal 'ab:cd', ENV['VAR']  # Delimiter ignored with -N
  end

  # -a array tests
  def test_read_into_array
    with_stdin("one two three\n") do
      Rubish::Builtins.run('read', ['-a', 'words'])
    end
    assert_equal 'one', ENV['words_0']
    assert_equal 'two', ENV['words_1']
    assert_equal 'three', ENV['words_2']
    assert_equal '3', ENV['words_LENGTH']
  end

  def test_read_array_clears_previous
    ENV['arr_0'] = 'old1'
    ENV['arr_1'] = 'old2'
    ENV['arr_2'] = 'old3'
    ENV['arr_LENGTH'] = '3'

    with_stdin("new\n") do
      Rubish::Builtins.run('read', ['-a', 'arr'])
    end

    assert_equal 'new', ENV['arr_0']
    assert_nil ENV['arr_1']
    assert_nil ENV['arr_2']
    assert_equal '1', ENV['arr_LENGTH']
  end

  def test_read_array_does_not_set_reply
    ENV.delete('REPLY')
    with_stdin("one two\n") do
      Rubish::Builtins.run('read', ['-a', 'arr'])
    end
    assert_nil ENV['REPLY']
  end

  # -t timeout tests
  def test_read_timeout_success
    with_stdin("quick\n") do
      result = Rubish::Builtins.run('read', ['-t', '5', 'VAR'])
      assert_true result
      assert_equal 'quick', ENV['VAR']
    end
  end

  def test_read_timeout_failure
    read_io, write_io = IO.pipe
    $stdin = read_io

    result = Rubish::Builtins.run('read', ['-t', '0.1', 'VAR'])
    assert_false result

    read_io.close
    write_io.close
  end

  # Combined options tests
  def test_read_with_prompt_and_raw
    $stderr = StringIO.new
    with_stdin("test\\nvalue\n") do
      Rubish::Builtins.run('read', ['-r', '-p', 'Input: ', 'VAR'])
    end
    assert_equal 'Input: ', $stderr.string
    assert_equal 'test\\nvalue', ENV['VAR']
  end

  def test_read_nchars_with_delimiter
    with_stdin('abc:defgh') do
      Rubish::Builtins.run('read', ['-n', '5', '-d', ':', 'VAR'])
    end
    assert_equal 'abc', ENV['VAR']  # Stops at delimiter before nchars
  end

  def test_read_timeout_with_nchars
    with_stdin('ab') do
      result = Rubish::Builtins.run('read', ['-t', '1', '-n', '2', 'VAR'])
      assert_true result
      assert_equal 'ab', ENV['VAR']
    end
  end

  # Helper method tests
  def test_process_read_escapes
    assert_equal 'hellotworld', Rubish::Builtins.process_read_escapes('hello\\tworld')
    assert_equal 'hello\\world', Rubish::Builtins.process_read_escapes('hello\\\\world')
    assert_equal 'hello', Rubish::Builtins.process_read_escapes('hello\\')
  end

  def test_store_read_variables
    Rubish::Builtins.store_read_variables(%w[a b c], 'one two three')
    assert_equal 'one', ENV['a']
    assert_equal 'two', ENV['b']
    assert_equal 'three', ENV['c']
  end

  def test_store_read_variables_remainder
    Rubish::Builtins.store_read_variables(%w[a b], 'one two three four')
    assert_equal 'one', ENV['a']
    assert_equal 'two three four', ENV['b']
  end

  def test_store_read_array
    Rubish::Builtins.store_read_array('arr', 'foo bar baz')
    assert_equal 'foo', ENV['arr_0']
    assert_equal 'bar', ENV['arr_1']
    assert_equal 'baz', ENV['arr_2']
    assert_equal '3', ENV['arr_LENGTH']
  end

  def test_clear_read_array
    ENV['arr_0'] = 'a'
    ENV['arr_1'] = 'b'
    ENV['arr_LENGTH'] = '2'

    Rubish::Builtins.clear_read_array('arr')

    assert_nil ENV['arr_0']
    assert_nil ENV['arr_1']
    assert_nil ENV['arr_LENGTH']
  end

  # Edge cases
  def test_read_whitespace_only_line
    with_stdin("   \n") do
      Rubish::Builtins.run('read', ['VAR'])
    end
    assert_equal '', ENV['VAR']
  end

  def test_read_preserves_inner_whitespace_in_last_var
    with_stdin("one   two   three\n") do
      Rubish::Builtins.run('read', %w[A B])
    end
    assert_equal 'one', ENV['A']
    assert_equal 'two   three', ENV['B']
  end
end
