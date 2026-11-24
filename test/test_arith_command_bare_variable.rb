# frozen_string_literal: true

require_relative 'test_helper'

# `(( x ))` with just a variable, or a quoted empty string, is arithmetic
class TestArithCommandBareVariable < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_bare_variable
    assert_equal "zero\nnz\n", run_shell('x=0; (( x )) || echo zero; x=2; (( x )) && echo nz')
  end

  def test_quoted_empty_expression
    assert_equal "1\n", run_shell('(( "" )); echo $?')
  end
end
