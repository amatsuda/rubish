# frozen_string_literal: true

require_relative 'test_helper'

# Job specs %%, %+, %- and %prefix name the current, previous and named jobs
class TestJobSpecForms < Test::Unit::TestCase
  def test_wait_and_kill
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'sleep 0.2 & sleep 0.3 & wait %%; echo "a=$?"; wait %-; echo "b=$?"; wait %sleep; echo "c=$?"; sleep 5 & kill %sle; wait %+; echo "d=$?"', err: err_w], &:read)
    err_w.close
    assert_equal "a=0\nb=0\nc=127\nd=143\n", out
    assert_equal "rubish: wait: %sleep: no such job\n", err_r.read
  ensure
    err_r&.close
  end
end
