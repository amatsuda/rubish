# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# With globstar, a bare `**` matches every file and directory below the
# current one, and `dir/**` includes `dir/` itself, as in bash
class TestGlobstarBare < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @dir = Dir.mktmpdir
    @old = Dir.pwd
    Dir.chdir(@dir)
    FileUtils.mkdir_p('d/e')
    FileUtils.touch(%w[d/x d/e/y])
  end

  def teardown
    Dir.chdir(@old)
    FileUtils.rm_rf(@dir)
    execute('shopt -u globstar')
  end

  def test_bare_double_star
    out = capture_stdout { execute('shopt -s globstar; echo **') }
    assert_equal "d d/e d/e/y d/x\n", out
  end

  def test_double_star_before_a_name
    out = capture_stdout { execute('shopt -s globstar; echo **/y') }
    assert_equal "d/e/y\n", out
  end

  def test_double_star_after_a_directory
    out = capture_stdout { execute('shopt -s globstar; echo d/**') }
    assert_equal "d/ d/e d/e/y d/x\n", out
  end
end
