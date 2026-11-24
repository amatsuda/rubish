# frozen_string_literal: true

require_relative 'test_helper'

# A word that is partly quoted still globs on its unquoted part
class TestGlobWithQuotedPart < Test::Unit::TestCase
  def test_quoted_prefix_and_suffix
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      Dir.mkdir("#{dir}/d")
      File.write("#{dir}/d/x", '')
      out = IO.popen([exe, '-c', %q{echo "d/"*; echo "d"/*; echo d/"x"*; echo "d/*"; /bin/echo "d/"*}, err: %i[child out]], chdir: dir, &:read)
      assert_equal "d/x\nd/x\nd/x\nd/*\nd/x\n", out
    end
  end
end
