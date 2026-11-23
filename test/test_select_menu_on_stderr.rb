# frozen_string_literal: true

require_relative 'test_helper'

# select writes its menu and PS3 prompt to stderr, as bash does
class TestSelectMenuOnStderr < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_menu_and_prompt_go_to_stderr
    out, err = run_shell('select x in a b; do echo "$x"; break; done <<< 2')
    assert_equal "b\n", out
    assert_equal "1) a\n2) b\n#? ", err
  end
end
