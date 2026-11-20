# frozen_string_literal: true

require_relative 'test_helper'

# set -o noclobber protects existing regular files only, not devices
class TestNoclobberDevices < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @dir = Dir.mktmpdir('rubish_noclobber')
    execute('set -o noclobber')
  end

  def teardown
    execute('set +o noclobber')
    FileUtils.rm_rf(@dir)
  end

  def test_writing_to_dev_null_is_allowed
    err = capture_stderr { execute('echo a > /dev/null') }
    assert_equal '', err
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end

  def test_existing_regular_file_is_still_protected
    f = File.join(@dir, 'f')
    File.write(f, 'keep')
    capture_stderr { execute("echo a > #{f}") }
    assert_equal 'keep', File.read(f)
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_new_file_is_allowed
    f = File.join(@dir, 'new')
    execute("echo a > #{f}")
    assert_equal "a\n", File.read(f)
  end
end
