# frozen_string_literal: true

require_relative 'test_helper'

class TestZshHistOptions < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_zsh_options = Rubish::Builtins.current_state.zsh_options.dup
    @tempdir = Dir.mktmpdir('rubish_zsh_hist_test')
    Reline::HISTORY.clear
    ENV.delete('HISTCONTROL')
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.current_state.zsh_options.clear
    @original_zsh_options.each { |k, v| Rubish::Builtins.current_state.zsh_options[k] = v }
    Reline::HISTORY.clear
    Rubish::Builtins.clear_history_transient
    FileUtils.rm_rf(@tempdir)
  end

  # hist_ignore_space

  def test_hist_ignore_space_keeps_in_memory_for_ctrl_p
    Rubish::Builtins.run('setopt', ['hist_ignore_space'])
    @repl.send(:add_to_history, ' secret')
    @repl.send(:add_to_history, 'visible')
    # Both entries are in memory (ctrl-p works)
    assert_equal 2, Reline::HISTORY.length
    assert_equal ' secret', Reline::HISTORY[0]
    assert_equal 'visible', Reline::HISTORY[1]
    # But the space-prefixed entry is marked transient (won't be saved to file)
    assert Rubish::Builtins.history_transient?(0)
    refute Rubish::Builtins.history_transient?(1)
  end

  def test_hist_ignore_space_with_started_with_space_flag
    Rubish::Builtins.run('setopt', ['hist_ignore_space'])
    @repl.send(:add_to_history, 'stripped', started_with_space: true)
    @repl.send(:add_to_history, 'normal')
    # Both in memory, but started_with_space entry is transient
    assert_equal 2, Reline::HISTORY.length
    assert Rubish::Builtins.history_transient?(0)
    refute Rubish::Builtins.history_transient?(1)
  end

  def test_hist_ignore_space_not_saved_to_file
    histfile = File.join(@tempdir, 'history')
    ENV['HISTFILE'] = histfile
    ENV['HISTFILESIZE'] = '1000'

    Rubish::Builtins.run('setopt', ['hist_ignore_space'])
    @repl.send(:add_to_history, ' secret')
    @repl.send(:add_to_history, 'visible')
    @repl.send(:save_history)

    lines = File.readlines(histfile, chomp: true)
    assert_equal ['visible'], lines
  end

  def test_hist_ignore_space_disabled_keeps_all
    Rubish::Builtins.run('unsetopt', ['hist_ignore_space'])
    @repl.send(:add_to_history, ' secret')
    @repl.send(:add_to_history, 'visible')
    assert_equal 2, Reline::HISTORY.length
    refute Rubish::Builtins.history_transient?(0)
    refute Rubish::Builtins.history_transient?(1)
  end

  # hist_ignore_dups

  def test_hist_ignore_dups_skips_consecutive
    Rubish::Builtins.run('setopt', ['hist_ignore_dups'])
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'pwd')
    @repl.send(:add_to_history, 'ls')
    assert_equal 3, Reline::HISTORY.length
    assert_equal ['ls', 'pwd', 'ls'], Reline::HISTORY.to_a
  end

  # hist_ignore_all_dups

  def test_hist_ignore_all_dups_removes_older
    Rubish::Builtins.run('setopt', ['hist_ignore_all_dups'])
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'pwd')
    @repl.send(:add_to_history, 'echo hello')
    @repl.send(:add_to_history, 'ls')
    assert_equal 3, Reline::HISTORY.length
    assert_equal ['pwd', 'echo hello', 'ls'], Reline::HISTORY.to_a
  end

  # hist_no_store

  def test_hist_no_store_skips_history_command
    Rubish::Builtins.run('setopt', ['hist_no_store'])
    @repl.send(:add_to_history, 'history')
    @repl.send(:add_to_history, 'history 0')
    @repl.send(:add_to_history, 'ls')
    assert_equal 1, Reline::HISTORY.length
    assert_equal 'ls', Reline::HISTORY[0]
  end

  def test_hist_no_store_disabled_keeps_history_command
    Rubish::Builtins.run('unsetopt', ['hist_no_store'])
    @repl.send(:add_to_history, 'history')
    @repl.send(:add_to_history, 'ls')
    assert_equal 2, Reline::HISTORY.length
  end

  # hist_reduce_blanks

  def test_hist_reduce_blanks_normalizes_whitespace
    Rubish::Builtins.run('setopt', ['hist_reduce_blanks'])
    @repl.send(:add_to_history, '  echo   hello    world  ')
    assert_equal 1, Reline::HISTORY.length
    assert_equal 'echo hello world', Reline::HISTORY[0]
  end

  # hist_save_no_dups

  def test_hist_save_no_dups_deduplicates_on_save
    histfile = File.join(@tempdir, 'history')
    ENV['HISTFILE'] = histfile
    ENV['HISTFILESIZE'] = '1000'

    Rubish::Builtins.run('setopt', ['hist_save_no_dups'])

    Reline::HISTORY << 'ls'
    Reline::HISTORY << 'pwd'
    Reline::HISTORY << 'ls'
    Reline::HISTORY << 'echo hello'

    @repl.send(:save_history)

    lines = File.readlines(histfile, chomp: true)
    assert_equal ['pwd', 'ls', 'echo hello'], lines
  end

  def test_hist_save_no_dups_disabled_keeps_all
    histfile = File.join(@tempdir, 'history')
    ENV['HISTFILE'] = histfile
    ENV['HISTFILESIZE'] = '1000'

    Rubish::Builtins.run('unsetopt', ['hist_save_no_dups'])

    Reline::HISTORY << 'ls'
    Reline::HISTORY << 'pwd'
    Reline::HISTORY << 'ls'

    @repl.send(:save_history)

    lines = File.readlines(histfile, chomp: true)
    assert_equal ['ls', 'pwd', 'ls'], lines
  end

  # hist_expire_dups_first

  def test_hist_expire_dups_first_removes_dups_when_trimming
    histfile = File.join(@tempdir, 'history')
    ENV['HISTFILE'] = histfile
    ENV['HISTFILESIZE'] = '3'

    Rubish::Builtins.run('setopt', ['hist_expire_dups_first'])

    Reline::HISTORY << 'ls'
    Reline::HISTORY << 'pwd'
    Reline::HISTORY << 'ls'
    Reline::HISTORY << 'echo hello'
    Reline::HISTORY << 'cat file'

    @repl.send(:save_history)

    lines = File.readlines(histfile, chomp: true)
    assert_equal 3, lines.length
    # The earlier 'ls' duplicate should be expired first, keeping unique entries
    assert_include lines, 'echo hello'
    assert_include lines, 'cat file'
  end

  # Combined options

  def test_hist_ignore_space_and_hist_ignore_all_dups
    Rubish::Builtins.run('setopt', ['hist_ignore_space'])
    Rubish::Builtins.run('setopt', ['hist_ignore_all_dups'])
    @repl.send(:add_to_history, ' secret')
    @repl.send(:add_to_history, 'ls')
    @repl.send(:add_to_history, 'pwd')
    @repl.send(:add_to_history, 'ls')
    # secret is transient (in memory but won't persist), dups are removed
    assert_equal 3, Reline::HISTORY.length
    assert_equal [' secret', 'pwd', 'ls'], Reline::HISTORY.to_a
    assert Rubish::Builtins.history_transient?(0)
    refute Rubish::Builtins.history_transient?(1)
    refute Rubish::Builtins.history_transient?(2)
  end

  def test_hist_reduce_blanks_and_hist_ignore_dups
    Rubish::Builtins.run('setopt', ['hist_reduce_blanks'])
    Rubish::Builtins.run('setopt', ['hist_ignore_dups'])
    @repl.send(:add_to_history, 'echo  hello')
    @repl.send(:add_to_history, 'echo hello')  # same after reduction
    assert_equal 1, Reline::HISTORY.length
    assert_equal 'echo hello', Reline::HISTORY[0]
  end
end
