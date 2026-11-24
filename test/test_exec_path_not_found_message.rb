# frozen_string_literal: true

require_relative 'test_helper'

# exec of a path that does not exist reports the system error, as bash does
class TestExecPathNotFoundMessage < Test::Unit::TestCase
  def test_messages
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'exec /nonexistent/x 2>&1 | head -1; (exec nosuch_q 2>&1) | head -1', err: %i[child out]], &:read)
    assert_equal "rubish: /nonexistent/x: No such file or directory\nrubish: exec: nosuch_q: not found\n", out
  end
end
