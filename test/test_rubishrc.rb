# frozen_string_literal: true

require_relative 'test_helper'

class TestRubishrc < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_rc_test')
    @saved_env = ENV.to_h
    @saved_home = ENV['HOME']
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @saved_env.each { |k, v| ENV[k] = v }
    # Clear any shell options set during the test
    Rubish::Builtins.shell_options.clear
  end

  # Test that config sets variables
  def test_rubishrc_sets_variables
    ENV['HOME'] = @tempdir
    rc_file = File.join(@tempdir, '.rubishrc')
    File.write(rc_file, "export TEST_RC_VAR=hello\n")

    @repl.send(:load_config)

    assert_equal 'hello', ENV['TEST_RC_VAR']
  end

  # Test that config defines aliases
  def test_rubishrc_defines_aliases
    ENV['HOME'] = @tempdir
    rc_file = File.join(@tempdir, '.rubishrc')
    File.write(rc_file, "alias ll='ls -la'\n")

    @repl.send(:load_config)

    assert Rubish::Builtins.aliases.key?('ll')
  end

  # Test for loop works
  def test_rubishrc_handles_for_loop
    ENV['HOME'] = @tempdir
    rc_file = File.join(@tempdir, '.rubishrc')
    File.write(rc_file, <<~RC)
      for i in a b c
      do
        export LOOP_TEST=$i
      done
    RC

    @repl.send(:load_config)

    assert_equal 'c', ENV['LOOP_TEST']
  end

  # Test comments are ignored
  def test_rubishrc_ignores_comments
    ENV['HOME'] = @tempdir
    rc_file = File.join(@tempdir, '.rubishrc')
    File.write(rc_file, <<~RC)
      # This is a comment
      export COMMENT_TEST=yes
      # Another comment
    RC

    @repl.send(:load_config)

    assert_equal 'yes', ENV['COMMENT_TEST']
  end

  # Test function definitions
  def test_rubishrc_defines_functions
    ENV['HOME'] = @tempdir
    rc_file = File.join(@tempdir, '.rubishrc')
    File.write(rc_file, <<~RC)
      greet() {
        echo hello
      }
    RC

    @repl.send(:load_config)

    assert @repl.functions.key?('greet')
  end

  # Test local .rubishrc in current directory
  def test_local_rubishrc
    ENV['HOME'] = @tempdir
    local_rc = File.join(Dir.pwd, '.rubishrc')

    begin
      File.write(local_rc, "export LOCAL_RC_VAR=local\n")
      @repl.send(:load_config)
      assert_equal 'local', ENV['LOCAL_RC_VAR']
    ensure
      FileUtils.rm_f(local_rc)
    end
  end

  # Test missing config file is OK
  def test_missing_rubishrc_no_error
    ENV['HOME'] = @tempdir
    # No .rubishrc file exists
    assert_nothing_raised { @repl.send(:load_config) }
  end

  # Test shopt settings
  def test_rubishrc_shopt_settings
    ENV['HOME'] = @tempdir
    rc_file = File.join(@tempdir, '.rubishrc')
    File.write(rc_file, "shopt -s extglob\n")

    @repl.send(:load_config)

    assert Rubish::Builtins.shell_options['extglob']
  end
end
