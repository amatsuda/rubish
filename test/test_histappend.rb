# frozen_string_literal: true

require_relative 'test_helper'

class TestHistappend < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @original_histfile = ENV['HISTFILE']
    @original_histfilesize = ENV['HISTFILESIZE']
    @tempdir = Dir.mktmpdir('rubish_histappend_test')
    @test_histfile = File.join(@tempdir, 'test_history')
    ENV['HISTFILE'] = @test_histfile
    ENV['HISTFILESIZE'] = '500'
    # Clear Reline history
    Reline::HISTORY.clear
    Rubish::Builtins.last_history_line = 0
  end

  def teardown
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    if @original_histfile
      ENV['HISTFILE'] = @original_histfile
    else
      ENV.delete('HISTFILE')
    end
    if @original_histfilesize
      ENV['HISTFILESIZE'] = @original_histfilesize
    else
      ENV.delete('HISTFILESIZE')
    end
    FileUtils.rm_rf(@tempdir)
    Reline::HISTORY.clear
  end

  def save_history
    @repl.send(:save_history)
  end

  def test_histappend_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('histappend')
  end

  def test_histappend_can_be_enabled
    execute('shopt -s histappend')
    assert Rubish::Builtins.shopt_enabled?('histappend')
  end

  def test_histappend_can_be_disabled
    execute('shopt -s histappend')
    execute('shopt -u histappend')
    assert_false Rubish::Builtins.shopt_enabled?('histappend')
  end

  def test_save_history_overwrites_when_histappend_disabled
    # Create existing history file
    File.write(@test_histfile, "old_command_1\nold_command_2\n")

    # Add commands to current session
    Reline::HISTORY << 'new_command_1'
    Reline::HISTORY << 'new_command_2'

    # Save history (histappend disabled by default)
    save_history

    # File should be overwritten with only session history
    lines = File.readlines(@test_histfile).map(&:chomp)
    assert_equal ['new_command_1', 'new_command_2'], lines
  end

  def test_save_history_appends_when_histappend_enabled
    # Create existing history file
    File.write(@test_histfile, "old_command_1\nold_command_2\n")

    # Enable histappend
    execute('shopt -s histappend')

    # Add commands to current session
    Reline::HISTORY << 'new_command_1'
    Reline::HISTORY << 'new_command_2'

    # Save history
    save_history

    # File should have old + new commands
    lines = File.readlines(@test_histfile).map(&:chomp)
    assert_equal ['old_command_1', 'old_command_2', 'new_command_1', 'new_command_2'], lines
  end

  def test_histappend_only_appends_new_entries
    # Create existing history file
    File.write(@test_histfile, "old_command\n")

    # Enable histappend
    execute('shopt -s histappend')

    # Add first command and mark it as saved
    Reline::HISTORY << 'first_new'
    Rubish::Builtins.last_history_line = Reline::HISTORY.size

    # Add second command (this is the "new" one)
    Reline::HISTORY << 'second_new'

    # Save history
    save_history

    # Only second_new should be appended
    lines = File.readlines(@test_histfile).map(&:chomp)
    assert_equal ['old_command', 'second_new'], lines
  end

  def test_histappend_respects_histfilesize
    ENV['HISTFILESIZE'] = '3'

    # Create existing history file with entries
    File.write(@test_histfile, "cmd1\ncmd2\n")

    # Enable histappend
    execute('shopt -s histappend')

    # Add new commands
    Reline::HISTORY << 'cmd3'
    Reline::HISTORY << 'cmd4'

    # Save history
    save_history

    # File should be truncated to last 3 entries
    lines = File.readlines(@test_histfile).map(&:chomp)
    assert_equal 3, lines.size
    assert_equal 'cmd4', lines.last
  end

  def test_histappend_creates_file_if_not_exists
    # Make sure file doesn't exist
    FileUtils.rm_f(@test_histfile)

    # Enable histappend
    execute('shopt -s histappend')

    # Add commands
    Reline::HISTORY << 'new_command'

    # Save history
    save_history

    # File should be created
    assert File.exist?(@test_histfile)
    lines = File.readlines(@test_histfile).map(&:chomp)
    assert_include lines, 'new_command'
  end
end
