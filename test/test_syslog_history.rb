# frozen_string_literal: true

require_relative 'test_helper'

class TestSyslogHistory < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('syslog_history_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic shopt option functionality

  def test_syslog_history_option_exists
    assert Rubish::Builtins::SHELL_OPTIONS.key?('syslog_history'),
           'syslog_history should be a valid shopt option'
  end

  def test_syslog_history_default_off
    assert_equal false, Rubish::Builtins::SHELL_OPTIONS['syslog_history'][0],
                 'syslog_history should be off by default'
  end

  def test_syslog_history_can_be_enabled
    execute('shopt -s syslog_history')
    assert Rubish::Builtins.shopt_enabled?('syslog_history'),
           'syslog_history should be enabled after shopt -s'
  end

  def test_syslog_history_can_be_disabled
    execute('shopt -s syslog_history')
    execute('shopt -u syslog_history')
    refute Rubish::Builtins.shopt_enabled?('syslog_history'),
           'syslog_history should be disabled after shopt -u'
  end

  def test_syslog_history_shown_in_shopt_list
    # Verify syslog_history is in the shell options list
    assert Rubish::Builtins::SHELL_OPTIONS.key?('syslog_history'),
           'syslog_history should appear in SHELL_OPTIONS'
  end

  def test_syslog_history_description
    desc = Rubish::Builtins::SHELL_OPTIONS['syslog_history'][1]
    assert_match(/syslog/i, desc, 'Description should mention syslog')
  end

  # Shopt query modes

  def test_shopt_q_syslog_history_returns_status
    # When disabled, shopt -q returns non-zero (false)
    execute('shopt -u syslog_history')
    execute('shopt -q syslog_history')
    refute_equal 0, @repl.instance_variable_get(:@last_status)

    # When enabled, shopt -q returns zero (true)
    execute('shopt -s syslog_history')
    execute('shopt -q syslog_history')
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  # Log method exists and is callable

  def test_log_to_syslog_method_exists
    assert @repl.respond_to?(:log_to_syslog, true),
           'REPL should have log_to_syslog method'
  end

  def test_log_to_syslog_does_not_raise
    # Should not raise even if syslog is unavailable
    assert_nothing_raised do
      @repl.send(:log_to_syslog, 'test command')
    end
  end

  # Integration with history

  def test_syslog_history_integrates_with_add_to_history
    # Enable syslog_history
    execute('shopt -s syslog_history')

    # This should not raise when adding to history
    assert_nothing_raised do
      @repl.send(:add_to_history, 'echo hello')
    end
  end

  def test_syslog_history_disabled_does_not_log
    # Ensure it's disabled
    execute('shopt -u syslog_history')

    # Track if log_to_syslog was called
    logged = false
    @repl.define_singleton_method(:log_to_syslog) { |_cmd| logged = true }

    @repl.send(:add_to_history, 'echo test')
    refute logged, 'Should not log when syslog_history is disabled'
  end

  def test_syslog_history_enabled_calls_log
    # Enable syslog_history
    execute('shopt -s syslog_history')

    # Track if log_to_syslog was called
    logged_command = nil
    @repl.define_singleton_method(:log_to_syslog) { |cmd| logged_command = cmd }

    @repl.send(:add_to_history, 'echo test')
    assert_equal 'echo test', logged_command, 'Should log command when syslog_history is enabled'
  end
end
