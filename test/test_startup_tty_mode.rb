# frozen_string_literal: true

require_relative 'test_helper'
require 'pty'

# Startup input buffering switches the terminal to raw mode while the
# shell boots and restores it before the first prompt. Both switches must
# be ordered deterministically: the raw switch synchronously before the
# reader thread starts, and the restore only after that thread is gone.
# Otherwise two stty processes race and the terminal can stay raw, turning
# the next Ctrl-C into a literal byte in front of the next command.
class TestStartupTtyMode < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @calls = []
    calls = @calls
    @repl.define_singleton_method(:run_stty) do |cmd|
      calls << [cmd, Thread.current == Thread.main, @stdin_buffer_thread&.alive? || false]
      true
    end
  end

  def with_tty_stdin
    PTY.open do |_master, slave|
      saved = $stdin
      $stdin = slave
      begin
        yield
      ensure
        $stdin = saved
      end
    end
  end

  def test_raw_mode_is_set_before_the_reader_thread_starts
    with_tty_stdin do
      @repl.send(:start_stdin_buffering)
      raw = @calls.find { |cmd, _, _| cmd == 'stty raw -echo' }
      assert_not_nil raw, "expected 'stty raw -echo' to have run when start_stdin_buffering returns; calls: #{@calls.inspect}"
      assert_true raw[1], 'raw mode must be switched on synchronously by the main thread'
    ensure
      @repl.send(:inject_buffered_input)
    end
  end

  def test_terminal_is_restored_only_after_the_reader_thread_stopped
    with_tty_stdin do
      @repl.send(:start_stdin_buffering)
      @repl.send(:inject_buffered_input)
      restore = @calls.reverse.find { |cmd, _, _| cmd != 'stty raw -echo' }
      assert_not_nil restore, "expected a restore call; calls: #{@calls.inspect}"
      assert_equal 'stty raw -echo', @calls.first[0], 'raw must come first'
      assert_false restore[2], 'the reader thread must be stopped before the terminal is restored'
    end
  end
end
