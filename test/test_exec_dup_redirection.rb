# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# `exec 2>&1` and `exec >&2` point the shell's own streams at each other;
# they never create a file named after the marker
class TestExecDupRedirection < Test::Unit::TestCase
  def run_shell(script, dir)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w, chdir: dir], &:read)
    err_w.close
    [out, err_r.read, $?.exitstatus]
  ensure
    err_r&.close
  end

  def test_exec_stderr_to_stdout
    Dir.mktmpdir do |dir|
      out, err, = run_shell('exec 2>&1; echo err >&2', dir)
      assert_equal "err\n", out
      assert_equal '', err
      assert_equal [], Dir.children(dir)
    end
  end

  def test_exec_stdout_to_stderr
    Dir.mktmpdir do |dir|
      out, err, = run_shell('exec >&2; echo out', dir)
      assert_equal '', out
      assert_equal "out\n", err
      assert_equal [], Dir.children(dir)
    end
  end

  def test_exec_of_a_missing_command_with_a_dup
    Dir.mktmpdir do |dir|
      out, _err, status = run_shell('exec nosuchcmd 2>&1; echo not reached', dir)
      assert_match(/nosuchcmd: not found/, out)
      assert_equal 127, status
      assert_equal [], Dir.children(dir)
    end
  end
end
