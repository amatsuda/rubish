# frozen_string_literal: true

require_relative 'test_helper'

# readonly -p shows `declare -r` lines; readonly -f and export -f complain
# about a name that is not a function
class TestReadonlyListingAndFunctions < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_readonly_p_marks_variables_readonly
    out = capture_stdout { execute('readonly ro_x=1; readonly -p') }
    assert_match(/^declare -r ro_x="1"$/, out)
  end

  def test_readonly_f_on_a_missing_function
    err = capture_stderr { @out = capture_stdout { execute('readonly -f no_such_fn; echo $?') } }
    assert_equal "1\n", @out
    assert_match(/readonly: no_such_fn: not a function/, err)
  end

  def test_export_f_on_a_missing_function
    err = capture_stderr { @out = capture_stdout { execute('export -f no_such_fn; echo $?') } }
    assert_equal "1\n", @out
    assert_match(/export: no_such_fn: not a function/, err)
  end

  def test_exported_function_reaches_a_child_bash
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'f() { echo fn $1; }; export -f f; bash -c "f x"', err: File::NULL], &:read)
    assert_equal "fn x\n", out
  end
end
