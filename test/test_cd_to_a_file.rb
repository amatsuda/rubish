# frozen_string_literal: true

require_relative 'test_helper'

# cd to something that is not a directory fails with "Not a directory"
class TestCdToAFile < Test::Unit::TestCase
  def test_message
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/f", '')
      err_r, err_w = IO.pipe
      out = IO.popen([exe, '-c', 'cd f; echo $?', err: err_w], chdir: dir, &:read)
      err_w.close
      assert_equal "1\n", out
      assert_equal "rubish: cd: f: Not a directory\n", err_r.read
    ensure
      err_r&.close
    end
  end
end
