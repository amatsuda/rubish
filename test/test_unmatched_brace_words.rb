# frozen_string_literal: true

require_relative 'test_helper'

# A brace that does not form a group or a brace expansion is an ordinary character
class TestUnmatchedBraceWords < Test::Unit::TestCase
  def test_literal_braces
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'echo ab{c,d; echo ab}c,d{; echo {a,b; echo a,b}; echo {a,b}c', err: %i[child out]], &:read)
    assert_equal "ab{c,d\nab}c,d{\n{a,b\na,b}\nac bc\n", out
  end
end
