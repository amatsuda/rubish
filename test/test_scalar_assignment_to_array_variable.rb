# frozen_string_literal: true

require_relative 'test_helper'

# `a=x` on an array variable assigns element 0 (bash)
class TestScalarAssignmentToArrayVariable < Test::Unit::TestCase
  def test_indexed_and_associative
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'declare -a a; a=x; echo "${a[0]} ${#a[@]}"; declare -A m; m=y; echo "[${m[0]}] ${#m[@]}"; b=(1 2 3); b=z; echo "${b[*]}"', err: %i[child out]], &:read)
    assert_equal "x 1\n[y] 1\nz 2 3\n", out
  end
end
