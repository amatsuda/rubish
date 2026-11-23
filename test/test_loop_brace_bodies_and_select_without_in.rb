# frozen_string_literal: true

require_relative 'test_helper'

# bash's alternative loop forms: a brace group as a for body, and
# `select name;` over the positional parameters
class TestLoopBraceBodiesAndSelectWithoutIn < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_arithmetic_for_with_a_brace_body
    assert_equal "0\n1\n2\n", run_shell('for ((i=0; i<3; i++)) { echo $i; }')
  end

  def test_for_in_with_a_brace_body
    assert_equal "1\n2\n", run_shell('for i in 1 2; { echo $i; }')
  end

  def test_select_without_in_uses_positional_parameters
    assert_equal "[q]\n", run_shell('set -- p q; select i; do echo "[$i]"; break; done <<< 2')
  end
end
