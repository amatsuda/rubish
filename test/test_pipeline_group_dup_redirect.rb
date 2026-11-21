# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# A brace group with `2>&1` as a pipeline element sends both streams down
# the pipe, like a subshell does
class TestPipelineGroupDupRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_brace_group_stderr_joins_stdout_in_pipeline
    Dir.mktmpdir('rubish_pgd') do |dir|
      out = File.join(dir, 'out.txt')
      execute("{ echo o; echo e >&2; } 2>&1 | sort > #{out}")
      assert_equal "e\no\n", File.read(out)
      assert_false File.exist?(File.join(Dir.pwd, '1'))
    end
  end

  def test_while_loop_stderr_joins_stdout_in_pipeline
    Dir.mktmpdir('rubish_pgd') do |dir|
      out = File.join(dir, 'out.txt')
      execute("n=0; while [ $n -lt 2 ]; do echo \"e$n\" >&2; n=$((n+1)); done 2>&1 | sort > #{out}")
      assert_equal "e0\ne1\n", File.read(out)
    end
  end
end
