# frozen_string_literal: true

require_relative 'test_helper'

class TestStartupInputBuffering < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    # Clean up any state
    Reline.pre_input_hook = nil
  end

  # Test that non-TTY stdin skips buffering entirely
  def test_start_stdin_buffering_skips_non_tty
    # In test environment, stdin is not a TTY
    @repl.send(:start_stdin_buffering)

    # Should not have started a thread
    assert_nil @repl.instance_variable_get(:@stdin_buffer_thread)
    assert_nil @repl.instance_variable_get(:@stdin_buffer)
  end

  # Test inject_buffered_input with no buffer
  def test_inject_buffered_input_with_no_buffer
    @repl.instance_variable_set(:@stdin_buffer, nil)
    @repl.instance_variable_set(:@stdin_buffer_thread, nil)

    # Should not raise and should not set pre_input_hook
    @repl.send(:inject_buffered_input)
    assert_nil Reline.pre_input_hook
  end

  # Test inject_buffered_input with empty buffer
  def test_inject_buffered_input_with_empty_buffer
    @repl.instance_variable_set(:@stdin_buffer, '')
    @repl.instance_variable_set(:@stdin_buffer_thread, nil)

    @repl.send(:inject_buffered_input)
    assert_nil Reline.pre_input_hook
  end

  # Test inject_buffered_input with incomplete text (no newline)
  def test_inject_buffered_input_with_incomplete_text
    @repl.instance_variable_set(:@stdin_buffer, 'echo hello')
    @repl.instance_variable_set(:@stdin_buffer_thread, nil)
    @repl.instance_variable_set(:@original_termios, nil)

    @repl.send(:inject_buffered_input)

    # Should set pre_input_hook
    assert_not_nil Reline.pre_input_hook

    # No pending commands (no complete lines)
    pending = @repl.instance_variable_get(:@pending_commands)
    assert_nil pending
  end

  # Test inject_buffered_input with complete command (has newline)
  def test_inject_buffered_input_with_complete_command
    @repl.instance_variable_set(:@stdin_buffer, "echo hello\n")
    @repl.instance_variable_set(:@stdin_buffer_thread, nil)
    @repl.instance_variable_set(:@original_termios, nil)

    @repl.send(:inject_buffered_input)

    # Should have pending command
    pending = @repl.instance_variable_get(:@pending_commands)
    assert_equal ['echo hello'], pending

    # No pre_input_hook (no incomplete text after newline)
    assert_nil Reline.pre_input_hook
  end

  # Test inject_buffered_input with multiple complete commands
  def test_inject_buffered_input_with_multiple_commands
    @repl.instance_variable_set(:@stdin_buffer, "echo one\necho two\necho three\n")
    @repl.instance_variable_set(:@stdin_buffer_thread, nil)
    @repl.instance_variable_set(:@original_termios, nil)

    @repl.send(:inject_buffered_input)

    pending = @repl.instance_variable_get(:@pending_commands)
    assert_equal ['echo one', 'echo two', 'echo three'], pending
    assert_nil Reline.pre_input_hook
  end

  # Test inject_buffered_input with commands and incomplete trailing text
  def test_inject_buffered_input_with_commands_and_trailing_text
    @repl.instance_variable_set(:@stdin_buffer, "echo one\necho two\npartial")
    @repl.instance_variable_set(:@stdin_buffer_thread, nil)
    @repl.instance_variable_set(:@original_termios, nil)

    @repl.send(:inject_buffered_input)

    # Complete commands become pending
    pending = @repl.instance_variable_get(:@pending_commands)
    assert_equal ['echo one', 'echo two'], pending

    # Incomplete text sets pre_input_hook
    assert_not_nil Reline.pre_input_hook
  end

  # Test that carriage returns are converted to newlines
  def test_inject_buffered_input_converts_cr_to_newline
    @repl.instance_variable_set(:@stdin_buffer, "echo one\recho two\r")
    @repl.instance_variable_set(:@stdin_buffer_thread, nil)
    @repl.instance_variable_set(:@original_termios, nil)

    @repl.send(:inject_buffered_input)

    pending = @repl.instance_variable_get(:@pending_commands)
    assert_equal ['echo one', 'echo two'], pending
  end

  # Test that empty lines are filtered out
  def test_inject_buffered_input_filters_empty_lines
    @repl.instance_variable_set(:@stdin_buffer, "echo one\n\n\necho two\n")
    @repl.instance_variable_set(:@stdin_buffer_thread, nil)
    @repl.instance_variable_set(:@original_termios, nil)

    @repl.send(:inject_buffered_input)

    pending = @repl.instance_variable_get(:@pending_commands)
    assert_equal ['echo one', 'echo two'], pending
  end

  # Test process_line executes pending commands
  def test_process_line_executes_pending_commands
    output = StringIO.new
    $stdout = output

    @repl.instance_variable_set(:@pending_commands, ['echo buffered_test'])

    # Mock the execute method to track calls
    executed = []
    @repl.define_singleton_method(:execute) do |line|
      executed << line
    end

    # Mock prompt to return simple string
    @repl.define_singleton_method(:prompt) { '$ ' }

    @repl.send(:process_line)

    assert_equal ['echo buffered_test'], executed
    assert @repl.instance_variable_get(:@pending_commands).empty?
  ensure
    $stdout = STDOUT
  end

  # Test process_line processes multiple pending commands in order
  def test_process_line_processes_pending_in_order
    executed = []
    @repl.define_singleton_method(:execute) do |line|
      executed << line
    end
    @repl.define_singleton_method(:prompt) { '$ ' }

    @repl.instance_variable_set(:@pending_commands, ['cmd1', 'cmd2', 'cmd3'])

    # Process three times
    $stdout = StringIO.new
    @repl.send(:process_line)
    @repl.send(:process_line)
    @repl.send(:process_line)
    $stdout = STDOUT

    assert_equal ['cmd1', 'cmd2', 'cmd3'], executed
    assert @repl.instance_variable_get(:@pending_commands).empty?
  ensure
    $stdout = STDOUT
  end

  # Test that buffered input is cleared after injection
  def test_stdin_buffer_cleared_after_injection
    @repl.instance_variable_set(:@stdin_buffer, 'test input')
    @repl.instance_variable_set(:@stdin_buffer_thread, nil)
    @repl.instance_variable_set(:@original_termios, nil)

    @repl.send(:inject_buffered_input)

    assert_nil @repl.instance_variable_get(:@stdin_buffer)
  end

  # Test thread cleanup with mock thread
  def test_inject_buffered_input_stops_thread
    mock_thread = Object.new
    stopped = false
    killed = false

    mock_thread.define_singleton_method(:join) { |_timeout| stopped = true }
    mock_thread.define_singleton_method(:alive?) { !killed }
    mock_thread.define_singleton_method(:kill) { killed = true }

    @repl.instance_variable_set(:@stdin_buffer, '')
    @repl.instance_variable_set(:@stdin_buffer_thread, mock_thread)
    @repl.instance_variable_set(:@stdin_buffering, true)
    @repl.instance_variable_set(:@original_termios, nil)

    @repl.send(:inject_buffered_input)

    assert stopped, 'Thread should have been joined'
    assert killed, 'Thread should have been killed'
    assert_equal false, @repl.instance_variable_get(:@stdin_buffering)
    assert_nil @repl.instance_variable_get(:@stdin_buffer_thread)
  end
end
