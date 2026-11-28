# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'timeout'

# A SIGINT the script does not trap ends a non-interactive shell as it
# ends bash: the EXIT trap runs, then the shell dies of the signal, with
# no Ruby backtrace for the Interrupt
class TestSigintNoninteractive < Test::Unit::TestCase
  EXE = File.expand_path('../exe/rubish', __dir__)
  LIB = File.expand_path('../lib', __dir__)

  # Run the shell in a process group of its own and send the group the
  # SIGINT a terminal's Ctrl-C would; answers the output and the status
  def interrupt(*args)
    reader, writer = IO.pipe
    pid = Process.spawn(RbConfig.ruby, '-I', LIB, EXE, *args, out: writer, err: writer, in: :close, pgroup: true)
    writer.close
    sleep 0.5
    Process.kill('INT', -pid)
    _, status = Process.wait2(pid)
    [Timeout.timeout(10) { reader.read }, status]
  ensure
    reader&.close
  end

  def test_command_string_dies_of_the_signal_quietly
    out, status = interrupt('-c', 'sleep 3; echo after')
    assert_equal '', out
    assert_equal Signal.list['INT'], status.termsig
  end

  def test_pipeline_dies_of_the_signal_quietly
    out, status = interrupt('-c', 'sleep 3 | cat; echo after')
    assert_equal '', out
    assert_equal Signal.list['INT'], status.termsig
  end

  def test_command_substitution_dies_of_the_signal_quietly
    out, status = interrupt('-c', 'x=$(sleep 3); echo after')
    assert_equal '', out
    assert_equal Signal.list['INT'], status.termsig
  end

  # $? there is the last finished command's status, as in bash 5.3
  def test_exit_trap_runs_before_the_shell_dies
    out, status = interrupt('-c', 'trap "echo bye \$?" EXIT; false; sleep 3; echo after')
    assert_equal "bye 1\n", out
    assert_equal Signal.list['INT'], status.termsig
  end

  def test_script_file_dies_of_the_signal_quietly
    Tempfile.create(['sigint', '.sh']) do |script|
      script.write("sleep 3\necho after\n")
      script.flush
      out, status = interrupt(script.path)
      assert_equal '', out
      assert_equal Signal.list['INT'], status.termsig
    end
  end

  def test_a_trapped_sigint_does_not_end_the_shell
    out, status = interrupt('-c', 'trap "echo trapped" INT; sleep 3; echo after')
    assert_equal "trapped\nafter\n", out
    assert_equal 0, status.exitstatus
  end
end
