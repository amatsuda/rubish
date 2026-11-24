# frozen_string_literal: true

require_relative 'test_helper'

# A pipeline element whose redirection names a closed descriptor does not run
class TestPipelineClosedFdRedirect < Test::Unit::TestCase
  def test_not_run
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      err_r, err_w = IO.pipe
      out = IO.popen([exe, '-c', 'exec 3>f; exec 3>&-; echo y >&3 | cat; echo "st=$?"; cat f', err: err_w], chdir: dir, &:read)
      err_w.close
      assert_equal "st=0\n", out
      assert_match(/3: Bad file descriptor/, err_r.read)
    ensure
      err_r&.close
    end
  end
end
