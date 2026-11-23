# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# source's exit status is that of `return N` in the file, or of its last command
class TestSourceStatus < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def script(content)
    path = File.join(@dir, 's.sh')
    File.write(path, content)
    path
  end

  def test_return_with_a_code
    path = script("echo in\nreturn 4\necho never\n")
    out = capture_stdout { execute("source #{path}; echo $?") }
    assert_equal "in\n4\n", out
  end

  def test_last_command_failing
    path = script("true\nfalse\n")
    out = capture_stdout { execute("source #{path}; echo $?") }
    assert_equal "1\n", out
  end

  def test_last_command_succeeding
    path = script("false\ntrue\n")
    out = capture_stdout { execute(". #{path}; echo $?") }
    assert_equal "0\n", out
  end
end
