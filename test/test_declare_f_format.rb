# frozen_string_literal: true

require_relative 'test_helper'

# declare -f and type print a function as bash does: `name () `, `{ `, the body, `}`
class TestDeclareFFormat < Test::Unit::TestCase
  def test_format
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'f() { echo hi; }; declare -f f; type f | tail -n +2', err: %i[child out]], &:read)
    assert_equal "f () \n{ \n    echo hi\n}\nf () \n{ \n    echo hi\n}\n", out
  end
end
