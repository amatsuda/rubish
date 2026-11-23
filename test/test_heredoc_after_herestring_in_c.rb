# frozen_string_literal: true

require_relative 'test_helper'

# In a -c string, a heredoc on a line that also has a herestring is read
class TestHeredocAfterHerestringInC < Test::Unit::TestCase
  def test_heredoc_body_is_found
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      out = IO.popen([exe, '-c', "cat <<< here > f; cat <<EOF > g\ndoc\nEOF\ncat f g", chdir: dir, err: File::NULL], &:read)
      assert_equal "here\ndoc\n", out
    end
  end
end
