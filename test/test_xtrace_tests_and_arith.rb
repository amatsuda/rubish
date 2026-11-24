# frozen_string_literal: true

require_relative 'test_helper'

# set -x traces [[ ]] and (( )) commands
class TestXtraceTestsAndArith < Test::Unit::TestCase
  def test_traced
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    IO.popen([exe, '-c', 'set -x; [[ a == a ]]; (( 1 + 1 ))', err: err_w], &:read)
    err_w.close
    assert_equal "+ [[ a == a ]]\n+ (( 1 + 1 ))\n", err_r.read
  ensure
    err_r&.close
  end
end
