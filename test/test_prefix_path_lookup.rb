# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# `PATH=dir cmd` looks cmd up in that PATH, not the shell's
class TestPrefixPathLookup < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', script, err: err_w], &:read)
    err_w.close
    [out, err_r.read]
  ensure
    err_r&.close
  end

  def test_command_missing_from_the_prefix_path_is_not_found
    out, err = run_shell('PATH=/nonexistent ls; echo $?')
    assert_equal "127\n", out
    assert_match(/ls: command not found/, err)
  end

  def test_command_is_found_in_the_prefix_path
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'hello'), "#!/bin/sh\necho from prefix path\n")
      File.chmod(0o755, File.join(dir, 'hello'))
      out, = run_shell("PATH=#{dir} hello")
      assert_equal "from prefix path\n", out
    end
  end
end
