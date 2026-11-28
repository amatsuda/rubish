# frozen_string_literal: true

require_relative 'test_helper'
require 'timeout'
require 'tmpdir'

# POSIX: in a shell without job control, a command run asynchronously
# ignores SIGINT and SIGQUIT, so a Ctrl-C meant for the foreground command
# (the whole process group gets it) does not take the job with it
class TestBackgroundJobSignals < Test::Unit::TestCase
  EXE = File.expand_path('../exe/rubish', __dir__)
  LIB = File.expand_path('../lib', __dir__)

  def rubish(script)
    out = IO.popen([RbConfig.ruby, '-I', LIB, EXE, '-c', script], err: [:child, :out], &:read)
    [out, $?]
  end

  def test_a_background_job_ignores_sigint_without_job_control
    out, = rubish('sleep 2 & kill -INT $!; sleep 0.3; jobs; kill -TERM $!')
    assert_match(/\[1\]\+\s+Running/, out, out)
    refute_match(/Interrupt|\.rb:\d+/, out, 'the job must not die, let alone with a Ruby backtrace')
  end

  def test_a_background_job_ignores_sigquit_without_job_control
    out, = rubish('sleep 2 & kill -QUIT $!; sleep 0.3; jobs; kill -TERM $!')
    assert_match(/\[1\]\+\s+Running/, out, out)
  end

  def test_a_background_job_still_dies_of_sigterm
    out, = rubish('sleep 2 & kill -TERM $!; sleep 0.3; jobs')
    assert_match(/\[1\]\+\s+Terminated/, out, out)
  end
  # A terminal's Ctrl-C goes to the whole process group: the external
  # command the job runs inherits the ignore through exec and runs on
  def test_the_jobs_commands_ignore_a_sigint_sent_to_the_process_group
    reader, writer = IO.pipe
    script = '(sleep 1 && echo slept-through) & sleep 3'
    pid = Process.spawn(RbConfig.ruby, '-I', LIB, EXE, '-c', script, out: writer, err: writer, in: :close, pgroup: true)
    writer.close
    sleep 0.5
    Process.kill('INT', -pid)
    Process.wait(pid)
    # The pipe reaches EOF once the job, which holds it too, has ended
    out = Timeout.timeout(10) { reader.read }
    assert_include out, 'slept-through'
  ensure
    reader&.close
  end
  # `( ... ) &` is a single process, as in bash, so $! is the subshell and
  # a signal sent to it reaches the trap the subshell set
  def test_a_signal_to_a_background_subshell_reaches_its_trap
    out, = rubish('( trap "echo trapped" INT; sleep 1; echo done ) & sleep 0.3; kill -INT $!; wait')
    assert_equal "trapped\ndone\n", out
  end

  def test_a_background_subshell_keeps_its_redirect_and_status
    Dir.mktmpdir('rubish_bg_subshell') do |dir|
      out, = rubish("cd #{dir}; (echo in-sub) > out & wait; cat out; (exit 3) & wait $!; echo $?")
      assert_equal "in-sub\n3\n", out
    end
  end
end
