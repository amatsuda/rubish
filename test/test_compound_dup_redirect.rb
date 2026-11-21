# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# `>&N`, `2>&N` and `2>>` on a compound command run in the shell process,
# applied in the order they were written, as for a simple command
class TestCompoundDupRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_dup_before_file_keeps_stderr_on_original_stdout
    Dir.mktmpdir('rubish_cdr') do |dir|
      out = File.join(dir, 'out.txt')
      execute("{ { echo o; echo e >&2; } 2>&1 >/dev/null; } > #{out}")
      assert_equal "e\n", File.read(out)
    end
  end

  def test_file_before_dup_sends_both_to_the_file
    Dir.mktmpdir('rubish_cdr') do |dir|
      out = File.join(dir, 'out.txt')
      execute("{ echo o; echo e >&2; } > #{out} 2>&1")
      assert_equal "o\ne\n", File.read(out)
    end
  end

  def test_stdout_to_stderr_before_stderr_to_file
    Dir.mktmpdir('rubish_cdr') do |dir|
      out = File.join(dir, 'out.txt')
      execute("{ { echo o; echo e >&2; } >&2 2>/dev/null; } 2> #{out}")
      assert_equal "o\n", File.read(out)
    end
  end

  def test_stderr_append
    Dir.mktmpdir('rubish_cdr') do |dir|
      out = File.join(dir, 'out.txt')
      execute("{ echo e1 >&2; } 2>> #{out}")
      execute("{ echo e2 >&2; } 2>> #{out}")
      assert_equal "e1\ne2\n", File.read(out)
    end
  end

  # The shell's real stdout: `2>&1` must copy it, not alias it, or the
  # following `>/dev/null` takes stderr along
  def test_dup_of_real_stdout_survives_later_stdout_redirect
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', '{ echo o; /bin/echo e >&2; } 2>&1 >/dev/null'], err: File::NULL, &:read)
    assert_equal "e\n", out
  end

  def test_while_loop_stderr_to_stdout_file
    Dir.mktmpdir('rubish_cdr') do |dir|
      out = File.join(dir, 'out.txt')
      execute("n=0; while [ $n -lt 2 ]; do echo \"e$n\" >&2; n=$((n+1)); done > #{out} 2>&1")
      assert_equal "e0\ne1\n", File.read(out)
    end
  end
end
