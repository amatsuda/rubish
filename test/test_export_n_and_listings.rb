# frozen_string_literal: true

require_relative 'test_helper'

# export -n removes the variable from the environment but keeps its value;
# export -p and readonly -p list in declare format, as bash does
class TestExportNAndListings < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    ENV.delete('EXN_T')
    ENV.delete('EXP_T')
  end

  def test_export_n_unexports_but_keeps_the_value
    execute('EXN_T=1; export EXN_T; export -n EXN_T')
    assert_nil ENV['EXN_T']
    assert_equal '1', get_shell_var('EXN_T')
  end

  def test_export_p_uses_declare_format
    execute('export EXP_T=v')
    out = capture_stdout { execute('export -p') }
    assert_includes out.lines, %(declare -x EXP_T="v"\n)
  end

  def test_readonly_p_uses_declare_format
    execute('readonly RO_T_LIST=1')
    out = capture_stdout { execute('readonly -p') }
    assert_includes out.lines, %(declare -r RO_T_LIST="1"\n)
  end
end
