# frozen_string_literal: true

require_relative 'test_helper'

# Readonly errors from unset and export read as bash's do
class TestReadonlyMessages < Test::Unit::TestCase
  def test_messages
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'readonly R=1; unset R; echo $?; export x=1; readonly x; export x=2; echo $?', err: err_w], &:read)
    err_w.close
    assert_equal "1\n1\n", out
    assert_equal "rubish: unset: R: cannot unset: readonly variable\nrubish: x: readonly variable\n", err_r.read
  ensure
    err_r&.close
  end
end
