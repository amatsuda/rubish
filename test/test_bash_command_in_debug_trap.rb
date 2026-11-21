# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Inside a DEBUG trap, BASH_COMMAND is the command about to run, for each
# simple command of a list
class TestBashCommandInDebugTrap < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('trap - DEBUG')
  end

  def test_each_command_of_a_list
    Dir.mktmpdir('rubish_dbg') do |dir|
      out = File.join(dir, 'out.txt')
      execute("trap 'echo \"dbg:$BASH_COMMAND\" >> #{out}' DEBUG")
      execute("echo one > /dev/null; echo two three > /dev/null")
      lines = File.read(out).lines.map(&:chomp)
      assert_include lines, 'dbg:echo one'
      assert_include lines, 'dbg:echo two three'
      assert_not_include lines, 'dbg:echo "dbg:$BASH_COMMAND" >> ' + out
    end
  end
end
