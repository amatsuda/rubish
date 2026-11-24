# frozen_string_literal: true

require_relative 'test_helper'

# jobs reports a finished job as Done (or Exit N) with the job's own text, once
class TestJobsDoneStatus < Test::Unit::TestCase
  def test_done_and_exit
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'true & sleep 0.2; jobs; jobs | wc -l | tr -d " "; false & sleep 0.2; jobs; sleep 5 & jobs; kill %1; wait', err: %i[child out]], &:read)
    assert_equal "[1]+  Done                       true\n0\n[1]+  Exit 1                     false\n[1]+  Running                    sleep 5 &\n", out
  end
end
