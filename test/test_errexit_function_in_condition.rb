# frozen_string_literal: true

require_relative 'test_helper'

# A function run as a condition is exempt from errexit throughout its body
class TestErrexitFunctionInCondition < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_if_condition
    assert_equal "in_f\nt\nend\n", run_shell('set -e; f() { false; echo in_f; }; if f; then echo t; fi; echo end')
  end

  def test_while_condition
    assert_equal "in_f\nw\n", run_shell('set -e; f() { false; echo in_f; }; while f; do break; done; echo w')
  end

  def test_negated_function
    assert_equal "in_f\nafter\n", run_shell('set -e; f() { false; echo in_f; }; ! f; echo after')
  end
end
