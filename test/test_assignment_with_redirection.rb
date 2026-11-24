# frozen_string_literal: true

require_relative 'test_helper'

# An assignment may carry redirections, alone or in a pipeline
class TestAssignmentWithRedirection < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_in_a_pipeline_it_runs_in_the_subshell
    assert_equal "[]\n", run_shell('c=2 2>&1 | head -1; echo "[$c]"')
  end

  def test_array_append_with_a_redirection
    assert_equal "2\n", run_shell('arr=(1); arr+=(3) 2>&1; echo ${#arr[@]}')
  end

  def test_scalar_with_a_redirection
    assert_equal "1\n", run_shell('x=1 >/dev/null; echo $x')
  end
end
