# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# A compound command with several redirections as a pipeline element:
# `{ ...; } >/dev/null 2>&1 | cat`
class TestPipelineCompoundRedirectChain < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_file_then_dup_silences_both
    Dir.mktmpdir('rubish_pcr') do |dir|
      out = File.join(dir, 'out.txt')
      execute("{ echo o; echo e >&2; } >/dev/null 2>&1 | cat > #{out}")
      assert_equal '', File.read(out)
    end
  end

  def test_dup_then_file_sends_stderr_down_the_pipe
    Dir.mktmpdir('rubish_pcr') do |dir|
      out = File.join(dir, 'out.txt')
      execute("{ echo o; echo e >&2; } 2>&1 >/dev/null | cat > #{out}")
      assert_equal "e\n", File.read(out)
    end
  end

  def test_simple_command_dup_then_file_sends_stderr_down_the_pipe
    Dir.mktmpdir('rubish_pcr') do |dir|
      out = File.join(dir, 'out.txt')
      execute("ls /nonexistent_rubish_zz 2>&1 >/dev/null | cat > #{out}")
      assert_match(/No such file or directory/, File.read(out))
    end
  end

  def test_loop_with_two_redirects_runs_once
    Dir.mktmpdir('rubish_pcr') do |dir|
      out = File.join(dir, 'out.txt')
      execute("for i in 1 2; do echo $i; echo e$i >&2; done 2>&1 >/dev/null | sort > #{out}")
      assert_equal "e1\ne2\n", File.read(out)
    end
  end
end
