# frozen_string_literal: true

require_relative 'test_helper'

# PIPESTATUS reflects the last command, simple or pipeline, from every path
# that runs commands; `$PIPESTATUS` alone is its first element
class TestPipestatusAfterSimpleCommands < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: File::NULL], &:read)
  end

  def test_scalar_is_the_first_element
    assert_equal "Hi\n0\n", run_shell('echo hi | tr h H; echo $PIPESTATUS')
  end

  def test_simple_command_resets_it
    assert_equal "1\n1\n0 1 0\n0\n", run_shell('false; echo "${PIPESTATUS[@]}"; (true | false); echo "${PIPESTATUS[@]}"; true | false | true; echo "${PIPESTATUS[@]}"; echo "${PIPESTATUS[@]}"')
  end

  def test_negated_pipeline_keeps_each_status
    assert_equal "0 0 1\n", run_shell('! echo a | false; echo $? ${PIPESTATUS[@]}')
  end
end
