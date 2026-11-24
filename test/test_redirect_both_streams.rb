# frozen_string_literal: true

require_relative 'test_helper'

# `&>file` and `&>>file` send stdout and stderr to the file (bash)
class TestRedirectBothStreams < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      IO.popen([exe, '-c', script, err: %i[child out]], chdir: dir, &:read)
    end
  end

  def test_builtin_and_group
    assert_equal "e\no\n[]\n", run_shell('{ echo o; echo e >&2; } &> f; sort f; echo "[$(echo y &>/dev/null)]"')
  end

  def test_append_and_external_command
    assert_equal "a\nb\nc\n", run_shell('echo a &> f; echo b &>> f; /bin/echo c &>> f; cat f')
  end

  def test_function
    assert_equal "e\no\n", run_shell('f() { echo o; echo e >&2; }; f &> g; sort g')
  end
end
