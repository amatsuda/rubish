# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Redirections apply left to right: `>&2` after `2>file` sends stdout to the
# file, and `2>&1 >file` sends stderr to the original stdout
class TestRedirectOrder < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_dup_to_stderr_after_stderr_was_redirected_follows_it
    Dir.mktmpdir('rubish_redir') do |dir|
      err = File.join(dir, 'err.txt')
      out = File.join(dir, 'out.txt')
      execute("env SHLVL=1 sh -c 'echo hi' 2>#{err} >&2 > #{out}")
      execute("env SHLVL=1 sh -c 'echo hi2' 2>#{err} >&2")
      assert_equal "hi2\n", File.read(err)
    end
  end

  def test_builtin_dup_to_stderr_after_stderr_was_redirected
    Dir.mktmpdir('rubish_redir') do |dir|
      err = File.join(dir, 'err.txt')
      execute("echo hi 2>#{err} >&2")
      assert_equal "hi\n", File.read(err)
    end
  end

  def test_swap_idiom_sends_stderr_to_original_stdout
    Dir.mktmpdir('rubish_redir') do |dir|
      out = File.join(dir, 'out.txt')
      captured = File.join(dir, 'captured.txt')
      execute("{ env SHLVL=1 sh -c 'echo o; echo e >&2' 2>&1 >#{out}; } > #{captured}")
      assert_equal "o\n", File.read(out)
      assert_equal "e\n", File.read(captured)
    end
  end

  def test_both_to_file_when_dup_comes_last
    Dir.mktmpdir('rubish_redir') do |dir|
      out = File.join(dir, 'out.txt')
      execute("env SHLVL=1 sh -c 'echo o; echo e >&2' >#{out} 2>&1")
      assert_equal %w[e o], File.read(out).split.sort
    end
  end
  def test_group_redirect_reaches_external_commands
    Dir.mktmpdir('rubish_group') do |dir|
      out = File.join(dir, 'out.txt')
      err = File.join(dir, 'err.txt')
      execute("{ env SHLVL=1 sh -c 'echo o'; echo b; } > #{out}")
      execute("{ env SHLVL=1 sh -c 'echo e >&2'; } 2> #{err}")
      assert_equal "o\nb\n", File.read(out)
      assert_equal "e\n", File.read(err)
    end
  end

  def test_loop_input_redirect_reaches_external_commands
    Dir.mktmpdir('rubish_group') do |dir|
      input = File.join(dir, 'in.txt')
      out = File.join(dir, 'out.txt')
      File.write(input, "first\nsecond\n")
      execute("while read -r line; do echo \"$line\"; env SHLVL=1 sh -c 'read x; echo got:$x'; done < #{input} > #{out}")
      assert_equal "first\ngot:second\n", File.read(out)
    end
  end
end
