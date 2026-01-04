# frozen_string_literal: true

require_relative 'test_helper'

class TestHistoryControl < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_history_test')
    # Clear history before each test
    Reline::HISTORY.clear
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Reline::HISTORY.clear
    FileUtils.rm_rf(@tempdir)
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

  # HISTFILE tests

  def test_history_file_default
    ENV.delete('HISTFILE')
    assert_equal File.expand_path('~/.rubish_history'), @repl.send(:history_file)
  end

  def test_history_file_custom
    ENV['HISTFILE'] = '/tmp/custom_history'
    assert_equal '/tmp/custom_history', @repl.send(:history_file)
  end

  def test_histsize_default
    ENV.delete('HISTSIZE')
    assert_equal 500, @repl.send(:histsize)
  end

  def test_histsize_custom
    ENV['HISTSIZE'] = '100'
    assert_equal 100, @repl.send(:histsize)
  end

  def test_histsize_empty
    ENV['HISTSIZE'] = ''
    assert_equal 500, @repl.send(:histsize)
  end

  def test_histfilesize_default
    ENV.delete('HISTFILESIZE')
    assert_equal 500, @repl.send(:histfilesize)
  end

  def test_histfilesize_custom
    ENV['HISTFILESIZE'] = '200'
    assert_equal 200, @repl.send(:histfilesize)
  end

  def test_load_history_from_file
    histfile = File.join(@tempdir, 'history')
    File.write(histfile, "ls\npwd\necho hello\n")
    ENV['HISTFILE'] = histfile

    @repl.send(:load_history)

    assert_equal 3, Reline::HISTORY.length
    assert_equal ['ls', 'pwd', 'echo hello'], Reline::HISTORY.to_a
  end

  def test_load_history_respects_histsize
    histfile = File.join(@tempdir, 'history')
    File.write(histfile, "cmd1\ncmd2\ncmd3\ncmd4\ncmd5\n")
    ENV['HISTFILE'] = histfile
    ENV['HISTSIZE'] = '3'

    @repl.send(:load_history)

    # Only last 3 entries should be loaded
    assert_equal 3, Reline::HISTORY.length
    assert_equal ['cmd3', 'cmd4', 'cmd5'], Reline::HISTORY.to_a
  end

  def test_load_history_zero_histsize_skips
    histfile = File.join(@tempdir, 'history')
    File.write(histfile, "ls\npwd\n")
    ENV['HISTFILE'] = histfile
    ENV['HISTSIZE'] = '0'

    @repl.send(:load_history)

    assert_equal 0, Reline::HISTORY.length
  end

  def test_load_history_nonexistent_file
    ENV['HISTFILE'] = File.join(@tempdir, 'nonexistent')

    # Should not raise error
    @repl.send(:load_history)
    assert_equal 0, Reline::HISTORY.length
  end

  def test_save_history_to_file
    histfile = File.join(@tempdir, 'history')
    ENV['HISTFILE'] = histfile

    Reline::HISTORY << 'ls'
    Reline::HISTORY << 'pwd'
    Reline::HISTORY << 'echo hello'

    @repl.send(:save_history)

    assert File.exist?(histfile)
    assert_equal "ls\npwd\necho hello\n", File.read(histfile)
  end

  def test_save_history_respects_histfilesize
    histfile = File.join(@tempdir, 'history')
    ENV['HISTFILE'] = histfile
    ENV['HISTFILESIZE'] = '2'

    Reline::HISTORY << 'cmd1'
    Reline::HISTORY << 'cmd2'
    Reline::HISTORY << 'cmd3'
    Reline::HISTORY << 'cmd4'

    @repl.send(:save_history)

    # Only last 2 entries should be saved
    assert_equal "cmd3\ncmd4\n", File.read(histfile)
  end

  def test_save_history_zero_histfilesize_skips
    histfile = File.join(@tempdir, 'history')
    ENV['HISTFILE'] = histfile
    ENV['HISTFILESIZE'] = '0'

    Reline::HISTORY << 'ls'

    @repl.send(:save_history)

    assert !File.exist?(histfile)
  end

  def test_save_history_creates_directory
    histfile = File.join(@tempdir, 'subdir', 'history')
    ENV['HISTFILE'] = histfile

    Reline::HISTORY << 'test'

    @repl.send(:save_history)

    assert File.exist?(histfile)
    assert_equal "test\n", File.read(histfile)
  end

  def test_save_history_overwrites_existing
    histfile = File.join(@tempdir, 'history')
    File.write(histfile, "old1\nold2\nold3\n")
    ENV['HISTFILE'] = histfile

    Reline::HISTORY << 'new1'
    Reline::HISTORY << 'new2'

    @repl.send(:save_history)

    assert_equal "new1\nnew2\n", File.read(histfile)
  end

  def test_load_and_save_roundtrip
    histfile = File.join(@tempdir, 'history')
    ENV['HISTFILE'] = histfile

    # Add some history and save
    Reline::HISTORY << 'first'
    Reline::HISTORY << 'second'
    @repl.send(:save_history)

    # Clear and reload
    Reline::HISTORY.clear
    @repl.send(:load_history)

    assert_equal 2, Reline::HISTORY.length
    assert_equal ['first', 'second'], Reline::HISTORY.to_a
  end

  def test_negative_histsize_skips_load
    histfile = File.join(@tempdir, 'history')
    File.write(histfile, "ls\npwd\n")
    ENV['HISTFILE'] = histfile
    ENV['HISTSIZE'] = '-1'

    @repl.send(:load_history)

    assert_equal 0, Reline::HISTORY.length
  end

  def test_negative_histfilesize_skips_save
    histfile = File.join(@tempdir, 'history')
    ENV['HISTFILE'] = histfile
    ENV['HISTFILESIZE'] = '-1'

    Reline::HISTORY << 'test'

    @repl.send(:save_history)

    assert !File.exist?(histfile)
  end
end
