# frozen_string_literal: true

require_relative 'test_helper'

# `$BASH_SOURCE` without a subscript is the first element, as for any array
class TestBashSourceScalar < Test::Unit::TestCase
  def test_in_a_sourced_file
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/s.sh", 'echo "[$BASH_SOURCE] [${BASH_SOURCE[0]}]"' + "\n")
      out = IO.popen([exe, '-c', '. s.sh', err: File::NULL], chdir: dir, &:read)
      assert_equal "[s.sh] [s.sh]\n", out
    end
  end
end
