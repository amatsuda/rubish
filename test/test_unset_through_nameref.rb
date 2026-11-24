# frozen_string_literal: true

require_relative 'test_helper'

# `unset ref` unsets the variable a nameref points at; `unset -n ref` unsets the nameref
class TestUnsetThroughNameref < Test::Unit::TestCase
  def test_unset
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'x=1; declare -n r=x; unset r; echo "[${x-unset}]"; y=2; declare -n r2=y; unset -n r2; echo "[${r2-unset}] $y"', err: %i[child out]], &:read)
    assert_equal "[unset]\n[unset] 2\n", out
  end
end
