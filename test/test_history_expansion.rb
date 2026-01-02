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

  # Word designators
  # :0 - command name
  def test_word_designator_zero
    add_history('grep pattern file.txt')
    assert_equal 'echo grep', expand('echo !!:0')
  end

  # :1, :2, etc. - nth argument
  def test_word_designator_number
    add_history('cp file1.txt file2.txt')
    assert_equal 'echo file1.txt', expand('echo !!:1')
    assert_equal 'echo file2.txt', expand('echo !!:2')
  end

  # :^ - first argument (same as :1)
  def test_word_designator_caret
    add_history('ls -la /tmp')
    assert_equal 'echo -la', expand('echo !!:^')
  end

  # :$ - last argument
  def test_word_designator_dollar
    add_history('grep -r pattern dir/')
    assert_equal 'cd dir/', expand('cd !!:$')
  end

  # :* - all arguments
  def test_word_designator_star
    add_history('echo one two three')
    assert_equal 'printf one two three', expand('printf !!:*')
  end

  # :n-m - range of words
  def test_word_designator_range
    add_history('cmd arg1 arg2 arg3 arg4')
    assert_equal 'echo arg1 arg2', expand('echo !!:1-2')
  end

  # :n- - from n to last-1
  def test_word_designator_range_from
    add_history('cmd arg1 arg2 arg3')
    assert_equal 'echo arg1 arg2', expand('echo !!:1-')
  end

  # :-n - from 0 to n
  def test_word_designator_range_to
    add_history('cmd arg1 arg2 arg3')
    assert_equal 'echo cmd arg1', expand('echo !!:-1')
  end

  # Modifiers
  # :h - head (dirname)
  def test_modifier_head
    add_history('cat /path/to/file.txt')
    assert_equal 'cd /path/to', expand('cd !$:h')
  end

  # :t - tail (basename)
  def test_modifier_tail
    add_history('vim /path/to/file.txt')
    assert_equal 'echo file.txt', expand('echo !$:t')
  end

  # :r - remove extension
  def test_modifier_remove_extension
    add_history('gcc source.c')
    assert_equal './source', expand('./!$:r')
  end

  # :e - extension only
  def test_modifier_extension
    add_history('file document.pdf')
    assert_equal 'echo pdf', expand('echo !$:e')
  end

  # :q - quote
  def test_modifier_quote
    add_history('echo hello world')
    # The whole command gets quoted
    result = expand('echo !!:q')
    assert_match(/echo.*hello.*world/, result)
  end

  # :s/old/new/ - substitute
  def test_modifier_substitute
    add_history('cat file.txt')
    assert_equal 'cat file.bak', expand('!!:s/txt/bak/')
  end

  def test_modifier_substitute_no_trailing_slash
    add_history('echo hello')
    assert_equal 'echo world', expand('!!:s/hello/world')
  end

  # :gs/old/new/ - global substitute
  def test_modifier_global_substitute
    add_history('echo foo foo foo')
    assert_equal 'echo bar bar bar', expand('!!:gs/foo/bar/')
  end

  # Chained modifiers
  def test_chained_modifiers
    add_history('vim /path/to/file.txt')
    assert_equal 'echo file', expand('echo !$:t:r')
  end

  # Word designator with modifier
  def test_word_designator_with_modifier
    add_history('cp /src/file.txt /dest/')
    assert_equal 'cat /src', expand('cat !!:1:h')
  end

  # :p - print only (prints and returns nil)
  def test_modifier_print_only
    add_history('rm important.txt')
    output = capture_output { @repl.send(:expand_history, '!!:p') }
    assert_match(/rm important\.txt/, output)
  end

  # Event designators with word designators
  def test_event_with_word_designator
    add_history('first command', 'second command')
    assert_equal 'echo first', expand('echo !1:0')
    assert_equal 'echo second', expand('echo !2:0')
  end

  def test_negative_event_with_word_designator
    add_history('alpha one', 'beta two', 'gamma three')
    assert_equal 'echo three', expand('echo !-1:1')
    assert_equal 'echo two', expand('echo !-2:1')
  end

  # String search with word designator
  def test_string_search_with_word_designator
    add_history('grep pattern file.txt', 'ls -la')
    assert_equal 'cat file.txt', expand('cat !grep:$')
  end
end
