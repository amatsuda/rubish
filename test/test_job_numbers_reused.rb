# frozen_string_literal: true

require_relative 'test_helper'

# Job numbers start over once the job table is empty (bash)
class TestJobNumbersReused < Test::Unit::TestCase
  def test_second_job_is_one
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'true & wait $!; sleep 5 & kill %1; wait %1 2>/dev/null; echo $?', err: %i[child out]], &:read)
    assert_equal "143\n", out
  end
end
