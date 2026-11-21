# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Builtins that change shell state keep their effect when they carry a
# redirect inside a command list: they must run in the shell, not a child
class TestStatefulBuiltinWithRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @start = Dir.pwd
  end

  def teardown
    Dir.chdir(@start)
    execute("cd #{@start}")
    execute('dirs -c')
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_stateful') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_pushd_with_redirect_in_a_list_changes_the_stack
    assert_equal "/tmp\n", run_and_read("pushd /tmp >/dev/null && pushd /usr >/dev/null && popd >/dev/null && pwd")
  end

  def test_mapfile_with_input_redirect_in_a_list
    Dir.mktmpdir('rubish_mapfile') do |dir|
      file = File.join(dir, 'in.txt')
      File.write(file, "l1\nl2\nl3\n")
      assert_equal "3 l2\n", run_and_read("mapfile -t ml < #{file}; echo \"${#ml[@]} ${ml[1]}\"")
    end
  end

  def test_getopts_with_redirect_in_a_list
    assert_equal "a 2\n", run_and_read("OPTIND=1; set -- -a; getopts a opt 2>/dev/null; echo \"$opt $OPTIND\"")
  end
end
