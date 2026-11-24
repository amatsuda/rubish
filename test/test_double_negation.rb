# frozen_string_literal: true

require_relative 'test_helper'

# `! !` negates twice
class TestDoubleNegation < Test::Unit::TestCase
  def test_statuses
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', '! ! true; echo $?; ! ! false; echo $?; ! ! ! true; echo $?', err: %i[child out]], &:read)
    assert_equal "0\n1\n1\n", out
  end
end
