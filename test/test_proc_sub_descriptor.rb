# frozen_string_literal: true

require_relative 'test_helper'
require 'timeout'

# Process substitution hands the command a /dev/fd/N path of a pipe, as
# bash does: the reader or writer child never waits for a FIFO to be
# opened, so `echo <(true)` leaves no process behind
class TestProcSubDescriptor < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    Timeout.timeout(10) { IO.popen([exe, '-c', script], &:read) }
  end

  def test_unread_substitution_does_not_block_the_shell
    assert_equal "1\n", run_shell('echo <(true) | grep -c /dev/fd')
  end

  def test_input_substitutions_are_readable
    assert_equal "a\nb\n", run_shell('cat <(echo a) <(echo b)')
  end

  def test_output_substitution_sees_end_of_file_when_the_command_ends
    assert_equal "x\n", run_shell('echo x > >(cat); wait')
  end
end
