# frozen_string_literal: true

require_relative 'test_helper'

# export -p lists each exported variable once, and declare -x lists them too
class TestExportListing < Test::Unit::TestCase
  def test_no_duplicates_and_declare_x
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', %q{x=1; export x; declare -x y=2; export -p | grep -cE '^declare -x (x="1"|y="2")$'; declare -x | grep -c '^declare -x y="2"$'}, err: %i[child out]], &:read)
    assert_equal "2\n1\n", out
  end
end
