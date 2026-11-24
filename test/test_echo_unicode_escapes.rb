# frozen_string_literal: true

require_relative 'test_helper'

# echo -e knows \uHHHH and \UHHHHHHHH
class TestEchoUnicodeEscapes < Test::Unit::TestCase
  def test_escapes
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', %q{echo -e '\U00000043B\x41'; echo -e 'é'}, err: %i[child out]], &:read)
    assert_equal "CBA\né\n", out
  end
end
