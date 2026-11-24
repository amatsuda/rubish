# frozen_string_literal: true

require_relative 'test_helper'

# `unset name` removes an indexed or associative array
class TestUnsetArrayVariable < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_indexed_array
    assert_equal "0 unset\n", run_shell('a=(1 2 3); unset a; echo "${#a[@]} ${a[@]-unset}"')
  end

  def test_associative_array
    assert_equal "0 unset\n", run_shell('declare -A m=([k]=v); unset m; echo "${#m[@]} ${m[k]-unset}"')
  end

  def test_declare_p_after_unset
    assert_equal "1\n", run_shell('a=(1 2); unset a; declare -p a > /dev/null 2>&1; echo $?')
  end
end
