# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# read on a last line without a newline assigns the data but returns 1, and
# at end of file it clears the variable, so `while read -r l || [ -n "$l" ]`
# visits every line and then stops
class TestReadEofPartialLine < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_partial_last_line_is_assigned_with_failure_status
    Dir.mktmpdir('rubish_read') do |dir|
      f = File.join(dir, 'in.txt')
      File.write(f, 'partial')
      execute("read -r v_pl < #{f}")
      assert_equal 1, @repl.instance_variable_get(:@last_status)
      assert_equal 'partial', get_shell_var('v_pl')
    end
  end

  def test_variable_is_cleared_at_end_of_file
    Dir.mktmpdir('rubish_read') do |dir|
      f = File.join(dir, 'empty.txt')
      File.write(f, '')
      execute('v_eof=stale')
      execute("read -r v_eof < #{f}")
      assert_equal '', get_shell_var('v_eof')
    end
  end

  def test_loop_idiom_terminates_and_sees_every_line
    Dir.mktmpdir('rubish_read') do |dir|
      f = File.join(dir, 'in.txt')
      out = File.join(dir, 'out.txt')
      File.write(f, "a\nb")
      Timeout.timeout(10) { execute("while IFS= read -r l || [ -n \"$l\" ]; do echo \"<$l>\"; done < #{f} > #{out}") }
      assert_equal "<a>\n<b>\n", File.read(out)
    end
  end
end
