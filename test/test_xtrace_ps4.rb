# frozen_string_literal: true

require_relative 'test_helper'

# xtrace lines start with the expanded PS4
class TestXtracePs4 < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_custom_ps4
    _out, err = run_shell("PS4='TRACE: '; set -x; : a; set +x")
    assert_equal "TRACE: : a\nTRACE: set +x\n", err
  end

  def test_default_ps4
    _out, err = run_shell('set -x; echo hi >/dev/null; set +x')
    assert_equal "+ echo hi\n+ set +x\n", err
  end
end
