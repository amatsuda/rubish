# frozen_string_literal: true

require_relative 'test_helper'

class TestCheckwinsize < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_lines = ENV['LINES']
    @original_columns = ENV['COLUMNS']
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    # Restore original values
    if @original_lines
      ENV['LINES'] = @original_lines
    else
      ENV.delete('LINES')
    end
    if @original_columns
      ENV['COLUMNS'] = @original_columns
    else
      ENV.delete('COLUMNS')
    end
  end

  def check_window_size
    @repl.send(:check_window_size)
  end

  def test_checkwinsize_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('checkwinsize')
  end

  def test_checkwinsize_can_be_enabled
    execute('shopt -s checkwinsize')
    assert Rubish::Builtins.shopt_enabled?('checkwinsize')
  end

  def test_checkwinsize_can_be_disabled
    execute('shopt -s checkwinsize')
    execute('shopt -u checkwinsize')
    assert_false Rubish::Builtins.shopt_enabled?('checkwinsize')
  end

  def test_check_window_size_updates_lines_and_columns
    # Clear existing values
    ENV.delete('LINES')
    ENV.delete('COLUMNS')

    # Call check_window_size directly
    check_window_size

    # If we have a console, LINES and COLUMNS should be set
    if IO.console
      assert_not_nil ENV['LINES']
      assert_not_nil ENV['COLUMNS']
      assert ENV['LINES'].to_i > 0
      assert ENV['COLUMNS'].to_i > 0
    end
  end

  def test_check_window_size_updates_to_current_terminal_size
    # Skip if no console available
    return unless IO.console

    winsize = IO.console.winsize
    return unless winsize

    expected_lines, expected_columns = winsize

    # Clear and check
    ENV.delete('LINES')
    ENV.delete('COLUMNS')
    check_window_size

    assert_equal expected_lines.to_s, ENV['LINES']
    assert_equal expected_columns.to_s, ENV['COLUMNS']
  end

  def test_checkwinsize_does_not_run_when_disabled
    # Set some known values
    ENV['LINES'] = '999'
    ENV['COLUMNS'] = '888'

    # Run a command with checkwinsize disabled
    execute('true')

    # Values should remain unchanged
    assert_equal '999', ENV['LINES']
    assert_equal '888', ENV['COLUMNS']
  end
end
