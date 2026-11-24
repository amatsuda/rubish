# frozen_string_literal: true

require_relative 'test_helper'

# An array cannot be converted between indexed and associative (bash)
class TestDeclareArrayConversionError < Test::Unit::TestCase
  def test_errors
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'declare -A m=([k]=v); declare -a m; echo $?; a=(1); declare -A a; echo $?', err: err_w], &:read)
    err_w.close
    assert_equal "1\n1\n", out
    assert_equal "rubish: declare: m: cannot convert associative to indexed array\nrubish: declare: a: cannot convert indexed to associative array\n", err_r.read
  ensure
    err_r&.close
  end
end
