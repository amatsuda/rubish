# frozen_string_literal: true

require_relative 'test_helper'

# BASH_SUBSHELL counts a command substitution as a subshell level
class TestBashSubshellInSubstitution < Test::Unit::TestCase
  def test_levels
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'echo $BASH_SUBSHELL $(echo $BASH_SUBSHELL); (echo $(echo $BASH_SUBSHELL)); echo $(/bin/echo $BASH_SUBSHELL)', err: %i[child out]], &:read)
    assert_equal "0 1\n2\n1\n", out
  end
end
