# frozen_string_literal: true

require_relative 'test_helper'

# ${1:offset:length} slices a positional parameter
class TestPositionalSubstring < Test::Unit::TestCase
  def test_slices
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'set -- hello world; echo "${1:1:2}" "${1:1}" "${2: -2}" "[${3:1}]"', err: %i[child out]], &:read)
    assert_equal "el ello ld []\n", out
  end
end
