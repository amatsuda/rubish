# frozen_string_literal: true

require_relative 'test_helper'

# The "[coproc] NAME pid" notice is for interactive shells only
class TestCoprocNoticeQuiet < Test::Unit::TestCase
  def test_no_notice_in_a_script
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'coproc C { cat; }; echo z >&${C[1]}; exec {C[1]}>&-; read r <&${C[0]}; echo $r; wait'], &:read)
    assert_equal "z\n", out
  end
end
