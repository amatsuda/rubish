# frozen_string_literal: true

require_relative 'test_helper'

class TestHistoryExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    Reline::HISTORY.clear
  end

  def teardown
    Reline::HISTORY.clear
  end

  def expand(line)
    result, _expanded = @repl.send(:expand_history, line)
    result
  end

  def add_history(*commands)
    commands.each { |cmd| Reline::HISTORY << cmd }
  end

  # !! - repeat last command
  def test_double_bang
    add_history('echo hello')
    assert_equal 'echo hello', expand('!!')
  end

  def test_double_bang_in_command
    add_history('ls -la')
    assert_equal 'echo ls -la', expand('echo !!')
  end

  # !$ - last argument of previous command
  def test_last_arg
    add_history('grep pattern file.txt')
    assert_equal 'cat file.txt', expand('cat !$')
  end

  def test_last_arg_single_arg
    add_history('cd /tmp')
    assert_equal 'ls /tmp', expand('ls !$')
  end

  # !^ - first argument of previous command
  def test_first_arg
    add_history('cp source.txt dest.txt')
    assert_equal 'cat source.txt', expand('cat !^')
  end

  # !* - all arguments of previous command
  def test_all_args
    add_history('echo one two three')
    assert_equal 'printf one two three', expand('printf !*')
  end

  # !n - command number n
  def test_command_number
    add_history('first', 'second', 'third')
    assert_equal 'first', expand('!1')
    assert_equal 'second', expand('!2')
    assert_equal 'third', expand('!3')
  end

  # !-n - nth previous command
  def test_negative_number
    add_history('first', 'second', 'third')
    assert_equal 'third', expand('!-1')
    assert_equal 'second', expand('!-2')
    assert_equal 'first', expand('!-3')
  end

  # !string - most recent command starting with string
  def test_starts_with
    add_history('echo hello', 'ls -la', 'echo goodbye')
    assert_equal 'echo goodbye', expand('!echo')
    assert_equal 'ls -la', expand('!ls')
  end

  def test_starts_with_partial
    add_history('grep pattern file.txt')
    assert_equal 'grep pattern file.txt', expand('!gr')
  end

  # !?string - most recent command containing string
  def test_contains
    add_history('cat file.txt', 'ls /tmp', 'echo hello world')
    assert_equal 'echo hello world', expand('!?world')
    assert_equal 'cat file.txt', expand('!?file')
  end

  def test_contains_with_trailing_question
    add_history('grep pattern file.txt')
    assert_equal 'grep pattern file.txt', expand('!?pattern?')
  end

  # ^old^new - quick substitution
  def test_quick_substitution
    add_history('echo hello world')
    assert_equal 'echo goodbye world', expand('^hello^goodbye')
  end

  def test_quick_substitution_trailing_caret
    add_history('echo hello world')
    assert_equal 'echo goodbye world', expand('^hello^goodbye^')
  end

  # Single quotes prevent expansion
  def test_no_expansion_in_single_quotes
    add_history('echo hello')
    assert_equal "echo '!!'", expand("echo '!!'")
  end

  def test_no_expansion_partial_single_quotes
    add_history('echo hello')
    # Only the part in quotes is protected
    assert_equal "echo hello '!!'", expand("!! '!!'")
  end

  # Empty history
  def test_empty_history
    assert_equal '!!', expand('!!')
  end

  # No expansion needed
  def test_no_expansion
    add_history('echo hello')
    assert_equal 'ls -la', expand('ls -la')
  end

  # Lone ! should be kept
  def test_lone_exclamation
    add_history('echo hello')
    assert_equal 'echo !', expand('echo !')
  end

  def test_exclamation_space
    add_history('echo hello')
    assert_equal 'echo ! hello', expand('echo ! hello')
  end

  # Multiple expansions in one line
  def test_multiple_expansions
    add_history('echo hello', 'ls file.txt')
    assert_equal 'cp file.txt /backup/file.txt', expand('cp !$ /backup/!$')
  end

  # Event not found
  def test_event_not_found_number
    add_history('echo hello')
    result = expand('!999')
    assert_nil result
  end

  def test_event_not_found_string
    add_history('echo hello')
    result = expand('!nonexistent')
    assert_nil result
  end

  # Parse command args
  def test_parse_command_args_simple
    args = @repl.send(:parse_command_args, 'echo hello world')
    assert_equal ['echo', 'hello', 'world'], args
  end

  def test_parse_command_args_quoted
    args = @repl.send(:parse_command_args, 'echo "hello world"')
    assert_equal ['echo', '"hello world"'], args
  end

  def test_parse_command_args_single_quoted
    args = @repl.send(:parse_command_args, "echo 'hello world'")
    assert_equal ['echo', "'hello world'"], args
  end
end
