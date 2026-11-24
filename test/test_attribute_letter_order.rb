# frozen_string_literal: true

require_relative 'test_helper'

# Attribute letters come in bash's order: a A i n r t x l u c
class TestAttributeLetterOrder < Test::Unit::TestCase
  def test_order
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'declare -lx l=A; echo ${l@a}; declare -xi v=1; declare -p v; declare -ir r=1; echo ${r@a}', err: File::NULL], &:read)
    assert_equal "xl\ndeclare -ix v=\"1\"\nir\n", out
  end
end
