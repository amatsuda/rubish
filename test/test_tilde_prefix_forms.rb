# frozen_string_literal: true

require_relative 'test_helper'

# Only a valid tilde-prefix expands: `~~5` and `~~x` stay as written
class TestTildePrefixForms < Test::Unit::TestCase
  def test_tilde_before_a_delimiter
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'echo ~; echo ~|cat; z=a:~; echo "$z"; echo ~"x"', err: File::NULL], &:read)
    home = Dir.home
    assert_equal "#{home}\n#{home}\na:#{home}\n~x\n", out
  end

  def test_double_tilde
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'echo $(( ~~5 )); echo ~~x; echo ~ | grep -c "^$HOME"', err: File::NULL], &:read)
    assert_equal "5\n~~x\n1\n", out
  end
end
