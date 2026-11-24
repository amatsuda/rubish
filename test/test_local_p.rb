# frozen_string_literal: true

require_relative 'test_helper'

# `local -p name` prints the local variable's declaration
class TestLocalP < Test::Unit::TestCase
  def test_print
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'f() { local x=1 y; local -p x; local -p y; }; f', err: %i[child out]], &:read)
    assert_equal "declare -- x=\"1\"\ndeclare -- y\n", out
  end
end
