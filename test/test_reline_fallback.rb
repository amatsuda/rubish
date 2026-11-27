# frozen_string_literal: true

require 'test/unit'
require 'open3'
require 'tmpdir'

# exe/rubish turns to RubyGems for reline when a plain require of it fails.
# A Ruby whose Gem knows no user_dir (Fluxpinel, whose Gem is a stub) must
# then say that reline is missing, and how to name it, not die of a
# NoMethodError
class TestRelineFallback < Test::Unit::TestCase
  EXE = File.expand_path('../exe/rubish', __dir__)

  def test_missing_reline_is_reported_when_gem_has_no_user_dir
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'rubygems.rb'), "module Gem; end\n")
      # reline is a default gem of Ruby 2.7 to 3.3, in the stdlib directory
      # even with gems disabled: a reline.rb ahead of it keeps the require
      # failing, as on a Ruby with no reline at all
      File.write(File.join(dir, 'reline.rb'), "raise LoadError, 'cannot load such file -- reline'\n")
      # under bundle exec, RUBYOPT would load bundler/setup into the child,
      # and Bundler expects the real Gem
      env = { 'RUBYOPT' => nil, 'RUBYLIB' => nil, 'BUNDLE_GEMFILE' => nil, 'BUNDLE_BIN_PATH' => nil }
      _out, err, status = Open3.capture3(env, RbConfig.ruby, '--disable-gems', '-I', dir, EXE, '-c', ':', stdin_data: '')
      assert_equal 1, status.exitstatus
      assert_not_match(/NoMethodError/, err)
      assert_match(/\Arubish: .*reline.*RUBYLIB/m, err)
    end
  end
end
