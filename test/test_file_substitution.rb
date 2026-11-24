# frozen_string_literal: true

require_relative 'test_helper'

# $(< file) expands to the file's contents, like $(cat file) but without a fork
class TestFileSubstitution < Test::Unit::TestCase
  def test_contents_and_missing_file
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/f", "l1\nl2\n\n")
      err_r, err_w = IO.pipe
      out = IO.popen([exe, '-c', 'x=$(<f); echo "[$x]"; echo "$(< f)" | wc -l | tr -d " "; y=$(<nosuch); echo "st=$?"', err: err_w], chdir: dir, &:read)
      err_w.close
      assert_equal "[l1\nl2]\n2\nst=1\n", out
      assert_match(/nosuch: No such file or directory/, err_r.read)
    ensure
      err_r&.close
    end
  end
end
