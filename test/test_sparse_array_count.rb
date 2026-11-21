# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# ${#arr[@]} counts the elements that are set, not the highest index + 1
class TestSparseArrayCount < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_sparse') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_unset_element_is_not_counted
    execute('a=(x y z)')
    execute("unset 'a[1]'")
    assert_equal "2 x z 0 2\n", run_and_read('echo "${#a[@]} ${a[@]} ${!a[@]}"')
  end

  def test_assignment_beyond_the_end_counts_only_set_elements
    execute('a=(x y z)')
    execute('a[5]=w')
    assert_equal "4 0 1 2 5\n", run_and_read('echo "${#a[@]} ${!a[@]}"')
  end

  def test_count_inside_a_command_list
    assert_equal "2\n", run_and_read("b=(x y z); unset 'b[0]'; echo \"${#b[@]}\"")
  end
end
