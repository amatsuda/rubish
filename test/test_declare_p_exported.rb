# frozen_string_literal: true

require_relative 'test_helper'

# declare -p shows -x for every exported variable, including ones inherited
# from the environment rather than exported in this shell
class TestDeclarePExported < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    ENV['RUBISH_INHERITED_TEST'] = 'from-env'
  end

  def teardown
    ENV.delete('RUBISH_INHERITED_TEST')
  end

  def test_inherited_environment_variable_is_shown_as_exported
    out = capture_stdout { execute('declare -p RUBISH_INHERITED_TEST') }
    assert_equal %(declare -x RUBISH_INHERITED_TEST="from-env"\n), out
  end

  def test_plain_shell_variable_has_no_export_flag
    execute('plain_var=1')
    out = capture_stdout { execute('declare -p plain_var') }
    assert_equal %(declare -- plain_var="1"\n), out
  end
end
