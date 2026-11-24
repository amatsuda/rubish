# frozen_string_literal: true

require_relative 'test_helper'

# declare rejects a name that is not a valid identifier
class TestDeclareInvalidIdentifier < Test::Unit::TestCase
  def test_rejected
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'declare -- -y=1; echo $?; declare 1x=2; echo $?; declare ok=3; echo $?', err: err_w], &:read)
    err_w.close
    assert_equal "1\n1\n0\n", out
    assert_equal "rubish: declare: `-y=1': not a valid identifier\nrubish: declare: `1x=2': not a valid identifier\n", err_r.read
  ensure
    err_r&.close
  end
end
