# frozen_string_literal: true

require_relative 'test_helper'

# A key with a space in a compound assignment: `declare -A m=([a b]=v)`
class TestAssocLiteralKeyWithSpace < Test::Unit::TestCase
  def test_key_with_space
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', %q{declare -A m=([a b]=v [c]=w); echo "${m[a b]}"; k='a b'; echo "${m[$k]}"; echo "${#m[@]}"}, err: File::NULL], &:read)
    assert_equal "v\nv\n2\n", out
  end
end
