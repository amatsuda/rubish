# frozen_string_literal: true

require_relative 'test_helper'

# shopt pads option names to 20 columns, shopt -o and set -o to 15 (bash)
class TestShoptListingWidth < Test::Unit::TestCase
  def test_widths
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'shopt nullglob; shopt -o errexit; set -o | grep errexit', err: %i[child out]], &:read)
    assert_equal "nullglob            \toff\nerrexit        \toff\nerrexit        \toff\n", out
  end
end
