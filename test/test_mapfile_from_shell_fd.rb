# frozen_string_literal: true

require_relative 'test_helper'

# mapfile -u reads from a descriptor opened with exec
class TestMapfileFromShellFd < Test::Unit::TestCase
  def test_exec_descriptor
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', %q{exec 3< <(printf 'l1\nl2\n'); mapfile -t -u 3 arr; echo "${#arr[@]} ${arr[1]}"; exec 3<&-; mapfile -u 9 x; echo $?}, err: %i[child out]], &:read)
    assert_equal "2 l2\nrubish: mapfile: 9: invalid file descriptor: Bad file descriptor\n1\n", out
  end
end
