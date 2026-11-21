# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# `N<<< word` opens the herestring on descriptor N; `N<file` and friends
# on a compound command last for the command's duration
class TestNumberedHerestring < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('exec 4<&- 3<&-')
  end

  def test_exec_opens_a_herestring_on_the_descriptor
    execute('exec 4<<< "from4"; read -u 4 v; exec 4<&-')
    assert_equal 'from4', Rubish::Builtins.get_var('v')
  end

  def test_external_command_reads_the_numbered_herestring
    Dir.mktmpdir('rubish_nh') do |dir|
      out = File.join(dir, 'out.txt')
      execute("cat 3<<< hi <&3 > #{out}")
      assert_equal "hi\n", File.read(out)
    end
  end

  def test_zero_is_an_alias_for_the_plain_herestring
    execute('read v 0<<< zero')
    assert_equal 'zero', Rubish::Builtins.get_var('v')
  end

  def test_loop_reads_a_numbered_herestring
    Dir.mktmpdir('rubish_nh') do |dir|
      out = File.join(dir, 'out.txt')
      execute("while read -u 3 l; do echo \"L:$l\" >> #{out}; done 3<<< $'a\\nb'")
      assert_equal "L:a\nL:b\n", File.read(out)
    end
  end

  def test_loop_reads_a_numbered_file
    Dir.mktmpdir('rubish_nh') do |dir|
      input = File.join(dir, 'in.txt')
      File.write(input, "p\nq\n")
      out = File.join(dir, 'out.txt')
      execute("while read -u 3 l; do echo \"L:$l\" >> #{out}; done 3< #{input}")
      assert_equal "L:p\nL:q\n", File.read(out)
    end
  end

  def test_descriptor_is_closed_after_the_compound_command
    Dir.mktmpdir('rubish_nh') do |dir|
      input = File.join(dir, 'in.txt')
      File.write(input, "p\n")
      execute("{ read -u 3 l; } 3< #{input}")
      assert_equal 'p', Rubish::Builtins.get_var('l')
      err = capture_stderr { execute('read -u 3 m') }
      assert_match(/invalid file descriptor/, err)
    end
  end
end
