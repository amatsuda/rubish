# frozen_string_literal: true

require_relative 'test_helper'

class TestHistoryControl < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    # Clear history before each test
    Reline::HISTORY.clear
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Reline::HISTORY.clear
  end

  # HISTCONTROL tests

  def test_no_histcontrol_adds_all
    ENV.delete('HISTCONTROL')
    @repl.send(:add_to_history, 'echo hello')
    @repl.send(:add_to_history, 'echo hello')
    @repl.send(:add_to_history, ' space')
    assert_equal 3, Reline::HISTORY.length
  end

  def test_histcontrol_ignorespace
    ENV['HISTCONTROL'] = 'ignorespace'
    @repl.send(:add_to_history, 'echo hello')
    @repl.send(:add_to_history, ' secret command')
    @repl.send(:add_to_history, '  double space')
    assert_equal 1, Reline::HISTORY.length
    assert_equal 'echo hello', Reline::HISTORY[0]
  end

  def test_histcontrol_ignoredups
    ENV['HISTCONTROL'] = 'ignoredups'
    @repl.send(:add_to_history, 'echo hello')
    @repl.send(:add_to_history, 'echo hello')
    @repl.send(:add_to_history, 'echo world')
    @repl.send(:add_to_history, 'echo hello')  # Not consecutive, should be added
    assert_equal 3, Reline::HISTORY.length
    assert_equal ['echo hello', 'echo world', 'echo hello'], Reline::HISTORY.to_a
  end

  def test_histcontrol_ignoreboth
    ENV['HISTCONTROL'] = 'ignoreboth'
    @repl.send(:add_to_history, 'echo hello')
    @repl.send(:add_to_history, 'echo hello')  # dup
    @repl.send(:add_to_history, ' secret')     # space
    @repl.send(:add_to_history, 'echo world')
    assert_equal 2, Reline::HISTORY.length
    assert_equal ['echo hello', 'echo world'], Reline::HISTORY.to_a
  end

  def test_histcontrol_erasedups
    ENV['HISTCONTROL'] = 'erasedups'
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'pwd')
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'echo hello')
    @repl.send(:add_to_history, 'ls')
    # 'ls' should only appear once at the end
    assert_equal 3, Reline::HISTORY.length
    assert_equal ['pwd', 'echo hello', 'ls'], Reline::HISTORY.to_a
  end

  def test_histcontrol_erasedups_and_ignorespace
    ENV['HISTCONTROL'] = 'erasedups:ignorespace'
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, ' secret')  # ignored
    @repl.send(:add_to_history, 'pwd')
    @repl.send(:add_to_history, 'ls')       # erases previous ls
    assert_equal 2, Reline::HISTORY.length
    assert_equal ['pwd', 'ls'], Reline::HISTORY.to_a
  end

  def test_histcontrol_multiple_values
    ENV['HISTCONTROL'] = 'ignorespace:ignoredups'
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'ls')       # dup - ignored
    @repl.send(:add_to_history, ' secret')  # space - ignored
    @repl.send(:add_to_history, 'pwd')
    assert_equal 2, Reline::HISTORY.length
  end

  def test_histcontrol_empty_string
    ENV['HISTCONTROL'] = ''
    @repl.send(:add_to_history, 'echo hello')
    @repl.send(:add_to_history, 'echo hello')
    assert_equal 2, Reline::HISTORY.length
  end

  # HISTIGNORE tests

  def test_histignore_exact_command
    ENV['HISTIGNORE'] = 'ls:pwd'
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'pwd')
    @repl.send(:add_to_history, 'echo hello')
    @repl.send(:add_to_history, 'ls -la')  # Has args, should be added
    assert_equal 2, Reline::HISTORY.length
    assert_equal ['echo hello', 'ls -la'], Reline::HISTORY.to_a
  end

  def test_histignore_glob_pattern
    ENV['HISTIGNORE'] = 'ls*'
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'ls -la')
    @repl.send(:add_to_history, 'lsof')
    @repl.send(:add_to_history, 'echo hello')
    assert_equal 1, Reline::HISTORY.length
    assert_equal 'echo hello', Reline::HISTORY[0]
  end

  def test_histignore_question_mark
    ENV['HISTIGNORE'] = 'l?'
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'la')
    @repl.send(:add_to_history, 'lsa')  # 3 chars, not matched
    @repl.send(:add_to_history, 'l')    # 1 char, not matched
    assert_equal 2, Reline::HISTORY.length
    assert_equal ['lsa', 'l'], Reline::HISTORY.to_a
  end

  def test_histignore_multiple_patterns
    ENV['HISTIGNORE'] = 'ls:cd *:exit'
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'cd /tmp')
    @repl.send(:add_to_history, 'exit')
    @repl.send(:add_to_history, 'echo hello')
    assert_equal 1, Reline::HISTORY.length
    assert_equal 'echo hello', Reline::HISTORY[0]
  end

  def test_histignore_empty
    ENV['HISTIGNORE'] = ''
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'pwd')
    assert_equal 2, Reline::HISTORY.length
  end

  def test_histignore_not_set
    ENV.delete('HISTIGNORE')
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'pwd')
    assert_equal 2, Reline::HISTORY.length
  end

  def test_histignore_with_spaces_in_pattern
    ENV['HISTIGNORE'] = 'echo test'
    @repl.send(:add_to_history, 'echo test')
    @repl.send(:add_to_history, 'echo hello')
    assert_equal 1, Reline::HISTORY.length
    assert_equal 'echo hello', Reline::HISTORY[0]
  end

  def test_histignore_complex_glob
    ENV['HISTIGNORE'] = '&:[ ]*:exit:history*'
    @repl.send(:add_to_history, 'exit')
    @repl.send(:add_to_history, 'history')
    @repl.send(:add_to_history, 'history -c')
    @repl.send(:add_to_history, 'echo hello')
    assert_equal 1, Reline::HISTORY.length
  end

  # Combined HISTCONTROL and HISTIGNORE

  def test_histcontrol_and_histignore_combined
    ENV['HISTCONTROL'] = 'ignorespace:ignoredups'
    ENV['HISTIGNORE'] = 'ls:pwd'
    @repl.send(:add_to_history, 'ls')        # ignored by HISTIGNORE
    @repl.send(:add_to_history, ' secret')   # ignored by ignorespace
    @repl.send(:add_to_history, 'echo hello')
    @repl.send(:add_to_history, 'echo hello') # ignored by ignoredups
    @repl.send(:add_to_history, 'pwd')       # ignored by HISTIGNORE
    @repl.send(:add_to_history, 'echo world')
    assert_equal 2, Reline::HISTORY.length
    assert_equal ['echo hello', 'echo world'], Reline::HISTORY.to_a
  end

  # Edge cases

  def test_empty_line_not_added
    ENV.delete('HISTCONTROL')
    @repl.send(:add_to_history, '')
    assert_equal 0, Reline::HISTORY.length
  end

  def test_whitespace_only_considered_space_prefix
    ENV['HISTCONTROL'] = 'ignorespace'
    @repl.send(:add_to_history, '  ls')  # starts with space
    assert_equal 0, Reline::HISTORY.length
  end

  def test_glob_to_regex_special_chars
    regex = @repl.send(:glob_to_regex, 'test.txt')
    assert regex.match?('test.txt')
    assert !regex.match?('testXtxt')
  end

  def test_glob_to_regex_star
    regex = @repl.send(:glob_to_regex, 'echo *')
    assert regex.match?('echo hello')
    assert regex.match?('echo hello world')
    assert !regex.match?('print hello')
  end

  def test_glob_to_regex_question
    regex = @repl.send(:glob_to_regex, 'l?')
    assert regex.match?('ls')
    assert regex.match?('la')
    assert !regex.match?('lsa')
    assert !regex.match?('l')
  end
end
