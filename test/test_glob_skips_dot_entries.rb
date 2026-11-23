# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# `.*` never yields `.` or `..` (bash 5.2 globskipdots default)
class TestGlobSkipsDotEntries < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @old = Dir.pwd
    @dir = Dir.mktmpdir
    Dir.chdir(@dir)
    FileUtils.touch(%w[.a .b c])
  end

  def teardown
    Dir.chdir(@old)
    FileUtils.rm_rf(@dir)
  end

  def test_dot_star
    out = capture_stdout { execute('echo .*') }
    assert_equal ".a .b\n", out
  end

  def test_dot_star_in_a_subdirectory
    out = capture_stdout { execute('mkdir s; touch s/.h; echo s/.*') }
    assert_equal "s/.h\n", out
  end
end
