# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Parameter expansion operators apply to array elements too:
# ${a[0]:-d}, ${a[1]:=d}, ${a[0]#x}, ${a[0]/x/y}, ${#a[0]}, ${m[k]^^} ...
class TestArrayElementOperators < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    execute('a=(xyz)')
    execute('declare -A m; m[k]=hello')
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_elem') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_default_on_set_and_unset_elements
    assert_equal "[xyz] [d] [d] [d]\n", run_and_read('echo "[${a[0]:-d}] [${a[1]:-d}] [${nosuch[0]:-d}] [${m[j]:-d}]"')
  end

  def test_default_unquoted_and_in_fast_path
    assert_equal "xyz d\n", run_and_read('echo ${a[0]:-d} ${a[1]:-d}')
    execute('v="${a[0]:-d}-${a[1]:-d}"')
    assert_equal 'xyz-d', get_shell_var('v')
  end

  def test_assign_default_sets_the_element
    assert_equal "d\n", run_and_read('echo "${a[1]:=d}"')
    assert_equal "d 2\n", run_and_read('echo "${a[1]} ${#a[@]}"')
    assert_equal "v\n", run_and_read('echo "${m[new]:=v}"')
    assert_equal "v\n", run_and_read('echo "${m[new]}"')
  end

  def test_alternate_value
    assert_equal "[set] []\n", run_and_read('echo "[${a[0]:+set}] [${a[1]:+set}]"')
  end

  def test_pattern_removal_and_replacement
    assert_equal "yz xy xQz\n", run_and_read('echo "${a[0]#x}" "${a[0]%z}" "${a[0]/y/Q}"')
  end

  def test_case_modification_and_length
    assert_equal "HELLO Hello 5 3\n", run_and_read('echo "${m[k]^^}" "${m[k]^}" "${#m[k]}" "${#a[0]}"')
  end

  def test_whole_array_default_when_empty
    execute('empty=()')
    assert_equal "none xyz\n", run_and_read('echo "${empty[@]:-none}" "${a[@]:-none}"')
  end
end
