# frozen_string_literal: true

require_relative 'test_helper'

# The last command of a list is traced once under set -x
class TestXtraceListLastCommandOnce < Test::Unit::TestCase
  def test_once
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    IO.popen([exe, '-c', 'set -x; true; echo a | cat; true; /usr/bin/true', err: err_w], &:read)
    err_w.close
    assert_equal "+ true\n+ echo a\n+ cat\n+ true\n+ /usr/bin/true\n", err_r.read
  ensure
    err_r&.close
  end
end
