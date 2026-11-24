# frozen_string_literal: true

require_relative 'test_helper'

# `type -P name` prints nothing for a name that is not in PATH
class TestTypePSilent < Test::Unit::TestCase
  def test_silent
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'type -P nosuch_q; echo $?; type -p nosuch_q; echo $?', err: %i[child out]], &:read)
    assert_equal "1\n1\n", out
  end
end
