# frozen_string_literal: true

require_relative 'test_helper'

# A fatal expansion error in one element of a pipeline ends that element
# only, as bash runs each element in a subshell; the shell goes on
class TestPipelineElementExpansionError < Test::Unit::TestCase
  def test_shell_goes_on
    exe = File.expand_path('../exe/rubish', __dir__)
    err_r, err_w = IO.pipe
    out = IO.popen([exe, '-c', 'echo $((1/0)) | cat; echo "st=$?"; echo "${u:?msg}" | cat; echo "st=$?"; : ${1:=2} | cat; echo "st=$?"; echo after', err: err_w], &:read)
    err_w.close
    assert_equal "st=0\nst=0\nst=0\nafter\n", out
    assert_equal 0, $?.exitstatus
    err = err_r.read
    assert_match(/division by 0/, err)
    assert_match(/u: msg/, err)
    assert_match(/cannot assign in this way/, err)
  ensure
    err_r&.close
  end
end
