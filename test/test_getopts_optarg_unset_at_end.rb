# frozen_string_literal: true

require_relative 'test_helper'

# When getopts runs out of options, OPTARG is unset (bash)
class TestGetoptsOptargUnsetAtEnd < Test::Unit::TestCase
  def test_unset
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'set -- -x; getopts :ab o; echo "$o $OPTARG"; set -- -a; getopts :a: o; echo "$o [${OPTARG-unset}]"', err: %i[child out]], &:read)
    assert_equal "? x\n? [unset]\n", out
  end
end
