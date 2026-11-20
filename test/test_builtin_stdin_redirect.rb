# frozen_string_literal: true

require_relative 'test_helper'

# A builtin with an input redirection reads from that file, in this process,
# so `read x < file` and `mapfile arr < file` set variables in the shell
class TestBuiltinStdinRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @dir = Dir.mktmpdir('rubish_builtin_stdin')
    @file = File.join(@dir, 'in.txt')
    File.write(@file, "first line\nsecond line\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
    Rubish::Builtins.unset(%w[x arr])
  end

  def test_read_from_file_as_lone_command
    execute("read x < #{@file}")
    assert_equal 'first line', get_shell_var('x')
  end

  def test_read_from_file_inside_a_list
    execute("true; read x < #{@file}")
    assert_equal 'first line', get_shell_var('x')
  end

  def test_shell_stdin_is_restored_afterwards
    execute("read x < #{@file}")
    assert_same STDIN, $stdin
  end
end
