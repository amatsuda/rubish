# frozen_string_literal: true

require_relative 'test_helper'

# An arithmetic syntax error is reported in bash's words, the expression trimmed
class TestArithmeticErrorWording < Test::Unit::TestCase
  def test_message
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    IO.popen([exe, '-c', 'echo $(( 1 + ))', err: err_w], &:read)
    err_w.close
    assert_match(/\Arubish: 1 \+ : arithmetic syntax error: operand expected/, err_r.read)
  ensure
    err_r&.close
  end
end
