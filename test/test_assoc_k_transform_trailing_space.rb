# frozen_string_literal: true

require_relative 'test_helper'

# ${m[@]@K} on an associative array ends each pair with a space, as bash prints it
class TestAssocKTransformTrailingSpace < Test::Unit::TestCase
  def test_trailing_space
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'declare -A m=([k]=v); echo "${m[@]@K}"', err: %i[child out]], &:read)
    assert_equal "k \"v\" \n", out
  end
end
