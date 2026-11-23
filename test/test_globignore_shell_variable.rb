# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# GLOBIGNORE works as a plain shell variable, exported or not
class TestGlobignoreShellVariable < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @old = Dir.pwd
    @dir = Dir.mktmpdir
    Dir.chdir(@dir)
    FileUtils.touch(%w[a.txt b.rb])
  end

  def teardown
    Dir.chdir(@old)
    FileUtils.rm_rf(@dir)
    execute('unset GLOBIGNORE')
  end

  def test_unexported_globignore
    out = capture_stdout { execute('GLOBIGNORE="*.txt"; echo *; unset GLOBIGNORE; echo *') }
    assert_equal "b.rb\na.txt b.rb\n", out
  end
end
