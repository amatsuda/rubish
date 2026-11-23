# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# cd searches CDPATH whether it is exported or a plain shell variable
class TestCdpathShellVariable < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @old = Dir.pwd
    @base = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@base, 'proj'))
    Dir.chdir(Dir.mktmpdir)
  end

  def teardown
    Dir.chdir(@old)
    FileUtils.rm_rf(@base)
    execute('unset CDPATH')
  end

  def test_unexported_cdpath_is_searched
    out = capture_stdout { execute("CDPATH=#{@base}; cd proj >/dev/null && pwd -P") }
    assert_equal "#{File.realpath(File.join(@base, 'proj'))}\n", out
  end
end
