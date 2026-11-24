# frozen_string_literal: true

require_relative 'test_helper'

# `alias -p` lists the aliases, and a name with a space or `/` is rejected
class TestAliasPAndInvalidName < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_p_lists
    out, = run_shell("alias x=1 y=2; alias -p")
    assert_equal "alias x='1'\nalias y='2'\n", out
  end

  def test_invalid_name
    out, err = run_shell("alias 'bad name'=x; echo $?; alias a/b=x; echo $?")
    assert_equal "1\n1\n", out
    assert_equal "rubish: alias: `bad name': invalid alias name\nrubish: alias: `a/b': invalid alias name\n", err
  end
end
