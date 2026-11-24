# frozen_string_literal: true

require_relative 'test_helper'

# `[ -o optname ]` tests a shell option, as in bash
class TestTestBuiltinOptionCheck < Test::Unit::TestCase
  def test_option
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', '[ -o nounset ]; echo $?; set -u; [ -o nounset ]; echo $?; [ ! -o nounset ]; echo $?; [ -o errexit -o -o nounset ]; echo $?', err: File::NULL], &:read)
    assert_equal "1\n0\n1\n0\n", out
  end
end
