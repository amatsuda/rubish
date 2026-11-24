# frozen_string_literal: true

require_relative 'test_helper'

# A sourced file sees the shell's $0; BASH_SOURCE names the file
class TestSourceKeepsDollarZero < Test::Unit::TestCase
  def test_dollar_zero
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/s.sh", "echo \"$0\"\necho \"${BASH_SOURCE[0]}\"\n")
      out = IO.popen([exe, '-c', 'echo "$0"; source s.sh; echo "$0"', err: %i[child out]], chdir: dir, &:read)
      zero, in_source, source_name, after = out.lines(chomp: true)
      assert_equal zero, in_source
      assert_equal 's.sh', source_name
      assert_equal zero, after
    end
  end
end
