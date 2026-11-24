# frozen_string_literal: true

require_relative 'test_helper'

# `local` with no arguments lists the function's local variables (bash)
class TestLocalListing < Test::Unit::TestCase
  def test_listing
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'f() { local a=1 b="2 3" c; local; }; f', err: %i[child out]], &:read)
    assert_equal "declare -- a=\"1\"\ndeclare -- b=\"2 3\"\ndeclare -- c\n", out
  end
end
