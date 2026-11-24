# frozen_string_literal: true

require_relative 'test_helper'

# Globs match names case-sensitively even on a case-insensitive filesystem (bash)
class TestGlobCaseSensitive < Test::Unit::TestCase
  def test_patterns
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/Abc", '')
      out = IO.popen([exe, '-c', 'echo [[:upper:]]*; echo [[:lower:]]*; echo [a-c]*; echo A*; echo a*; shopt -s nocaseglob; echo a*', err: %i[child out]], chdir: dir, &:read)
      assert_equal "Abc\n[[:lower:]]*\n[a-c]*\nAbc\na*\nAbc\n", out
    end
  end
end
