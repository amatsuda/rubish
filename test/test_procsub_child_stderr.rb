# frozen_string_literal: true

require_relative 'test_helper'

# The command inside <(...) or >(...) keeps the shell's stderr, as in bash
class TestProcsubChildStderr < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_output_substitution_writing_to_stderr
    _out, err = run_shell('exec 4> >(cat >&2); echo to4 >&4; exec 4>&-; sleep 0.3')
    assert_equal "to4\n", err
  end

  def test_input_substitution_error_is_visible
    _out, err = run_shell('cat <(ls /nonexistent_dir_q 2>&1 >/dev/null | sed "s/^/E:/"); sleep 0.2')
    assert_match(/E:.*No such file/, _out + err)
  end
end
