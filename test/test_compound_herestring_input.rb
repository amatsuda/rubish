# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# A herestring or heredoc feeds a compound command running in the shell
# process: `{ read l; ...; } <<< hi`, `while read l; do ...; done <<EOF`
class TestCompoundHerestringInput < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_brace_group_reads_herestring
    execute('{ read l; } <<< hi')
    assert_equal 'hi', Rubish::Builtins.get_var('l')
  end

  def test_brace_group_herestring_sets_variable_in_the_shell
    Dir.mktmpdir('rubish_chi') do |dir|
      out = File.join(dir, 'out.txt')
      execute("{ read l; echo \"got $l\"; } <<< hi > #{out}")
      assert_equal "got hi\n", File.read(out)
    end
  end

  def test_while_read_loop_over_herestring
    Dir.mktmpdir('rubish_chi') do |dir|
      out = File.join(dir, 'out.txt')
      execute("while read l; do echo \"L:$l\" >> #{out}; done <<< $'a\\nb'")
      assert_equal "L:a\nL:b\n", File.read(out)
    end
  end

  def test_external_command_in_the_group_reads_the_herestring
    Dir.mktmpdir('rubish_chi') do |dir|
      out = File.join(dir, 'out.txt')
      execute("{ read l; cat; } <<< $'first\\nrest' > #{out}")
      assert_equal "rest\n", File.read(out)
    end
  end

  def test_while_read_loop_over_heredoc
    exe = File.expand_path('../exe/rubish', __dir__)
    script = "while read l; do echo \"L:$l\"; done <<EOF\na\nb\nEOF\n"
    out = IO.popen([exe, '-c', script], err: File::NULL, &:read)
    assert_equal "L:a\nL:b\n", out
  end
end
