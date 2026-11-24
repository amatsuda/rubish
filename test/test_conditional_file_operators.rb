# frozen_string_literal: true

require_relative 'test_helper'

# [[ ]] knows -a, -p, -S, -c, -b, -O and -G
class TestConditionalFileOperators < Test::Unit::TestCase
  def test_operators
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir do |dir|
      out = IO.popen([exe, '-c', 'touch f; mkfifo p; [[ -a f ]] && echo exists; [[ -p p ]] && echo pipe; [[ -S /dev/null ]] || echo notsock; [[ -c /dev/null ]] && echo chr; [[ -b /dev/null ]] || echo notblk; [[ -O f ]] && echo owner; [[ -G f ]] && echo group', err: %i[child out]], chdir: dir, &:read)
      assert_equal "exists\npipe\nnotsock\nchr\nnotblk\nowner\ngroup\n", out
    end
  end
end
