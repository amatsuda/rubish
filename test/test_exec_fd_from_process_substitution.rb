# frozen_string_literal: true

require_relative 'test_helper'

# `exec 3< <(cmd)` opens descriptor 3 on the substitution's output
class TestExecFdFromProcessSubstitution < Test::Unit::TestCase
  def test_read_from_the_descriptor
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'exec 3< <(echo pfd); read x <&3; echo $x; exec 3<&-'], &:read)
    assert_equal "pfd\n", out
  end
end
