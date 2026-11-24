# frozen_string_literal: true

require_relative 'test_helper'

# `read -d ''` reads up to a NUL byte
class TestReadNulDelimiter < Test::Unit::TestCase
  def test_nul_delimited_records
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', %q{printf 'a\0b\0' | { read -d '' x; echo "$x"; read -d '' y; echo "$y"; }}, err: %i[child out]], &:read)
    assert_equal "a\nb\n", out
  end
end
