# frozen_string_literal: true

require_relative 'test_helper'

# $SHELLOPTS lists the enabled set -o options
class TestShelloptsVariable < Test::Unit::TestCase
  def test_listing
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'echo "$SHELLOPTS" | tr : "\n" | grep -c "^braceexpand$"; set -e; echo "$SHELLOPTS" | tr : "\n" | grep -c "^errexit$"', err: %i[child out]], &:read)
    assert_equal "1\n1\n", out
  end
end
