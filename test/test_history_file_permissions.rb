# frozen_string_literal: true

require_relative 'test_helper'

# The history file is private to the user (0600), like bash's
class TestHistoryFilePermissions < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_history_perms')
    @histfile = File.join(@tempdir, 'history')
    @original_histfile = ENV['HISTFILE']
    @original_histfilesize = ENV['HISTFILESIZE']
    ENV['HISTFILE'] = @histfile
    ENV['HISTFILESIZE'] = '500'
    Reline::HISTORY.clear
    Reline::HISTORY << 'echo secret command'
  end

  def teardown
    Reline::HISTORY.clear
    FileUtils.rm_rf(@tempdir)
    @original_histfile ? ENV['HISTFILE'] = @original_histfile : ENV.delete('HISTFILE')
    @original_histfilesize ? ENV['HISTFILESIZE'] = @original_histfilesize : ENV.delete('HISTFILESIZE')
  end

  def mode(path)
    File.stat(path).mode & 0o777
  end

  def test_save_history_creates_private_file
    @repl.send(:save_history)
    assert_match(/echo secret command/, File.read(@histfile))
    assert_equal 0o600, mode(@histfile)
  end

  def test_append_history_creates_private_file
    Rubish::Builtins.last_history_line = 0
    @repl.send(:append_history)
    assert_equal 0o600, mode(@histfile)
  end

  def test_histappend_mode_creates_private_file
    execute('shopt -s histappend')
    @repl.send(:save_history)
    assert_equal 0o600, mode(@histfile)
  ensure
    execute('shopt -u histappend')
  end
end
