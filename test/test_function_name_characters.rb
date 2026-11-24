# frozen_string_literal: true

require_relative 'test_helper'

# Function names may hold `-` and `.`, as bash allows
class TestFunctionNameCharacters < Test::Unit::TestCase
  def test_dash_and_dot
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'foo-bar() { echo dash; }; foo-bar; a.b() { echo dot; }; a.b', err: %i[child out]], &:read)
    assert_equal "dash\ndot\n", out
  end
end
