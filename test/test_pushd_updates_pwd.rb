# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# pushd and popd change directory like cd: PWD and OLDPWD follow, so `pwd`
# and prompts show the new directory
class TestPushdUpdatesPwd < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @start = Dir.pwd
  end

  def teardown
    Dir.chdir(@start)
    execute('dirs -c')
    execute("cd #{@start}")
  end

  def test_pushd_updates_pwd_and_oldpwd
    Dir.mktmpdir('rubish_pushd') do |dir|
      real = File.realpath(dir)
      capture_stdout { execute("pushd #{real}") }
      assert_equal real, get_shell_var('PWD')
      assert_equal @start, get_shell_var('OLDPWD')
      assert_equal "#{real}\n", capture_stdout { execute('pwd') }
      capture_stdout { execute('popd') }
      assert_equal @start, get_shell_var('PWD')
      assert_equal real, get_shell_var('OLDPWD')
    end
  end

  def test_pushd_with_redirect_in_a_list
    Dir.mktmpdir('rubish_pushd2') do |dir|
      real = File.realpath(dir)
      out = capture_stdout { execute("pushd #{real} >/dev/null && pwd") }
      assert_equal "#{real}\n", out
    end
  end
end
