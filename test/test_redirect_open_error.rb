# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# A redirection target that cannot be opened (a directory, a device that
# refuses the open) is reported like a missing file: a message, status 1,
# and the shell goes on
class TestRedirectOpenError < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_output_to_a_directory_is_reported
    err = capture_stderr { capture_stdout { execute("echo x > #{@dir}; echo $?") } }
    assert_match(/rubish: #{Regexp.escape(@dir)}: Is a directory/, err)
  end

  def test_output_to_a_directory_fails_the_command
    out = capture_stdout { capture_stderr { execute("echo x > #{@dir}; echo $?") } }
    assert_equal "1\n", out
  end

  def test_append_to_a_directory_is_reported
    err = capture_stderr { capture_stdout { execute("echo x >> #{@dir}") } }
    assert_match(/Is a directory/, err)
  end

  def test_compound_output_to_a_directory_is_reported
    err = capture_stderr { capture_stdout { execute("{ echo x; } > #{@dir}; echo $?") } }
    assert_match(/Is a directory/, err)
  end
end
