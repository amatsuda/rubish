# frozen_string_literal: true

require_relative 'test_helper'

# set -u: an unset associative array element is an error, a set one is not
class TestNounsetAssocElement < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_unset_element_is_reported
    out, err = run_shell('set -u; declare -A m=([a]=1); echo "${m[a]}" "${m[k]:-none}"; echo "${m[k]}"; echo not')
    assert_equal "1 none\n", out
    assert_match(/m\[k\]: unbound variable/, err)
  end
end
