# frozen_string_literal: true

require_relative 'test_helper'

# With lastpipe, a brace group or loop as the last pipeline element runs in
# the current shell, so what it reads stays
class TestLastpipeCompoundLastElement < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_brace_group_sets_variables_in_the_shell
    out, err = run_shell('shopt -s lastpipe; printf "p\nq\n" | { read l; cat; }; echo "[$l]"')
    assert_equal "q\n[p]\n", out
    assert_equal '', err
  end

  def test_while_loop_as_last_element
    out, = run_shell('shopt -s lastpipe; n=0; printf "a\nb\n" | while read x; do n=$((n+1)); done; echo $n')
    assert_equal "2\n", out
  end
end
