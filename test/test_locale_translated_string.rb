# frozen_string_literal: true

require_relative 'test_helper'

# $"..." is a double-quoted string (no translation catalogue here)
class TestLocaleTranslatedString < Test::Unit::TestCase
  def test_echo_and_assignment
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', %q{echo $"literal"; x=$"v w"; echo "$x"; y=1; echo $"y=$y"}, err: %i[child out]], &:read)
    assert_equal "literal\nv w\ny=1\n", out
  end
end
