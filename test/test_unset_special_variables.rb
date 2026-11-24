# frozen_string_literal: true

require_relative 'test_helper'

# unset SECONDS or RANDOM takes away the special meaning (bash)
class TestUnsetSpecialVariables < Test::Unit::TestCase
  def test_unset
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'unset SECONDS; echo "[${SECONDS:-u}]"; SECONDS=5; sleep 0; echo $SECONDS; unset RANDOM; echo "[${RANDOM:-u}]"', err: %i[child out]], &:read)
    assert_equal "[u]\n5\n[u]\n", out
  end
end
