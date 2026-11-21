# frozen_string_literal: true

require_relative 'test_helper'
require 'pty'
require 'timeout'
require 'tmpdir'

# An interactive shell must stay the terminal's foreground process group
# while background jobs run and finish; otherwise reading the next line
# fails with EIO and the prompt loop spins
class TestBackgroundJobTerminal < Test::Unit::TestCase
  EXE = File.expand_path('../exe/rubish', __dir__)
  LIB = File.expand_path('../lib', __dir__)

  def interactive_shell
    Dir.mktmpdir('rubish_pty') do |home|
      env = {'HOME' => home, 'TERM' => 'xterm', 'LANG' => 'en_US.UTF-8'}
      PTY.spawn(env, RbConfig.ruby, '-I', LIB, EXE, '--norc') do |reader, writer, pid|
        begin
          yield reader, writer, pid
        ensure
          Process.kill('KILL', pid) rescue nil
          # macOS does not let the session leader finish exiting until the pty
          # master has been drained, so read to EOF before reaping
          Timeout.timeout(5) { loop { reader.readpartial(4096) } } rescue nil
          Process.wait(pid) rescue nil
        end
      end
    end
  end

  def read_until(reader, pattern, timeout: 10)
    buffer = +''
    Timeout.timeout(timeout) do
      buffer << reader.readpartial(4096) until buffer.match?(pattern)
    end
    buffer
  rescue Timeout::Error
    flunk "timed out waiting for #{pattern.inspect}; got: #{buffer.gsub(/\e\[[0-9;?]*[A-Za-z]/, '')[-300..] || buffer}"
  end

  def test_shell_still_reads_input_after_background_job_finishes
    interactive_shell do |reader, writer, _pid|
      read_until(reader, /\$ /)
      writer.write("sleep 0.3 &\r")
      read_until(reader, /\[1\] \d+/)
      sleep 0.6
      writer.write("\r") # like bash, the job notice is printed before the next prompt
      read_until(reader, /Done/)
      writer.write("echo still $((40 + 2))\r")
      read_until(reader, /still 42/)
    end
  end

  def test_background_job_does_not_take_the_terminal_from_the_shell
    interactive_shell do |reader, writer, pid|
      read_until(reader, /\$ /)
      writer.write("sleep 1 &\r")
      read_until(reader, /\[1\] \d+/)
      sleep 0.3
      foreground_pgid, shell_pgid = IO.popen(['ps', '-o', 'tpgid=,pgid=', '-p', pid.to_s], &:read).split
      assert_equal shell_pgid, foreground_pgid, 'the shell must still own the terminal while the job runs'
    end
  end
end
