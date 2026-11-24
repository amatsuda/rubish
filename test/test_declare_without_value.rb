# frozen_string_literal: true

require_relative 'test_helper'

# `declare x` declares x without setting it: declare -p shows it, ${x-unset} does not
class TestDeclareWithoutValue < Test::Unit::TestCase
  def test_declared_but_unset
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'unset x n; declare x; declare -p x; echo "[${x-unset}]"; declare -i n; declare -p n', err: %i[child out]], &:read)
    assert_equal "declare -- x\n[unset]\ndeclare -i n\n", out
  end
end
