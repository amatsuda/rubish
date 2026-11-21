# frozen_string_literal: true

require_relative 'test_helper'

# `read -u N` with a descriptor the shell has not opened is an error, not a
# crash
class TestReadBadFd < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_unopened_descriptor_is_reported
    # A descriptor number that is certainly closed: the one just released
    file = File.open(__FILE__)
    fd = file.fileno
    file.close
    err = capture_stderr { execute("read -u #{fd} v") }
    assert_equal "rubish: read: #{fd}: invalid file descriptor: Bad file descriptor\n", err
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end
end
