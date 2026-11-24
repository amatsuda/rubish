# frozen_string_literal: true

require_relative 'test_helper'

# A quoted or escaped command name with a space runs the file it names
class TestCommandNameWithSpace < Test::Unit::TestCase
  def test_quoted_and_escaped_names
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/s p.sh", "echo x\n")
      File.chmod(0o755, "#{dir}/s p.sh")
      # stderr is dropped: the script's sh warns about the test suite's SHLVL
      out = IO.popen([exe, '-c', %q{"./s p.sh"; './s p.sh'; ./s\ p.sh}, err: File::NULL], chdir: dir, &:read)
      assert_equal "x\nx\nx\n", out
    end
  end
end
