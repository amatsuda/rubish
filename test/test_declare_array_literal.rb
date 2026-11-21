# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# `declare -a name=(...)`, `declare -A name=([k]=v ...)`, `local -a` and
# `readonly name=(...)` take a compound array value, as in bash
class TestDeclareArrayLiteral < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_decl') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_declare_A_with_literal_creates_the_associative_array
    execute('declare -A m=([k]=v [j]=w)')
    assert_equal "2 v w\n", run_and_read('echo "${#m[@]} ${m[k]} ${m[j]}"')
  end

  def test_declare_a_with_literal_keeps_quoted_elements_together
    execute('declare -a l=(x "y z")')
    assert_equal "2 y z\n", run_and_read('echo "${#l[@]} ${l[1]}"')
  end

  def test_elements_are_expanded
    execute('q=val')
    execute('declare -a l=($q "$q$q")')
    assert_equal "val valval\n", run_and_read('echo "${l[@]}"')
  end

  def test_following_command_on_the_same_line_still_runs
    assert_equal "after x\n", run_and_read('declare -a l=(x y); echo after ${l[0]}')
  end

  def test_local_array_literal_is_scoped_to_the_function
    execute('f() { local -a loc=(1 2 3); echo "${#loc[@]}"; }')
    assert_equal "3\n", run_and_read('f')
    assert_equal "0\n", run_and_read('echo "${#loc[@]}"')
  end

  def test_readonly_array_literal
    execute('readonly ro=(a b)')
    assert_equal "a b\n", run_and_read('echo "${ro[@]}"')
    err = capture_stderr { execute('readonly ro=(c)') }
    assert_match(/readonly/, err)
  end

  def test_typeset_and_append
    execute('typeset -a t=(1)')
    execute('declare -a t+=(2 3)')
    assert_equal "1 2 3\n", run_and_read('echo "${t[@]}"')
  end
end
