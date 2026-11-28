# frozen_string_literal: true

require_relative 'test_helper'

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
end
