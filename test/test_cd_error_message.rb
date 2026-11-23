# frozen_string_literal: true

require_relative 'test_helper'

# cd names the directory in its error, as bash does
class TestCdErrorMessage < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_missing_directory
    err = capture_stderr { @out = capture_stdout { execute('cd /nonexistent; echo $?') } }
    assert_equal "1\n", @out
    assert_equal "rubish: cd: /nonexistent: No such file or directory\n", err
  end
end
