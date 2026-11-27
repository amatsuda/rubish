# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'

# The shell runs as `ruby exe/rubish`, but process listings should name it
# rubish, followed by its arguments, as they show `bash script.sh`
class TestProcessTitle < Test::Unit::TestCase
  EXE = File.expand_path('../exe/rubish', __dir__)
  LIB = File.expand_path('../lib', __dir__)

  def test_process_listing_names_the_shell_rubish
    out, _status = Open3.capture2(RbConfig.ruby, '-I', LIB, EXE, '-c', 'ps -o command= -p $$', stdin_data: '')
    assert_match(/\Arubish -c ps -o command= -p \$\$\s*\z/, out)
  end
end
