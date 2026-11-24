# frozen_string_literal: true

require_relative 'test_helper'

# ${!#} is the last positional parameter (indirection through $#)
class TestIndirectLastPositional < Test::Unit::TestCase
  def test_last_positional
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'set -- a b c; echo "${!#}"; set -- x; echo "${!#}"', err: %i[child out]], &:read)
    assert_equal "c\nx\n", out
  end
end
