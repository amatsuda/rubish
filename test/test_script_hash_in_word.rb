# frozen_string_literal: true

require_relative 'test_helper'

# `$#` in a script line is not a comment for the structure tracker
class TestScriptHashInWord < Test::Unit::TestCase
  def test_no_warning
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/s.sh", "f() { echo $#; }; f a b\necho ok # real comment\n")
      out = IO.popen([exe, "#{dir}/s.sh", err: %i[child out]], &:read)
      assert_equal "2\nok\n", out
    end
  end
end
