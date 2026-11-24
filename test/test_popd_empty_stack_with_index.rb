# frozen_string_literal: true

require_relative 'test_helper'

# `popd +N` on an empty stack reports the empty stack (bash)
class TestPopdEmptyStackWithIndex < Test::Unit::TestCase
  def test_message
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'popd +5; echo $?', err: err_w], &:read)
    err_w.close
    assert_equal "1\n", out
    assert_equal "rubish: popd: directory stack empty\n", err_r.read
  ensure
    err_r&.close
  end
end
