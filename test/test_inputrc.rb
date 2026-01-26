# frozen_string_literal: true

require_relative 'test_helper'

class TestINPUTRC < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_inputrc_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    # Reset Reline config to avoid affecting other tests
    Reline.core.config.reset_variables if defined?(Reline)
  end

  def inputrc_path
    @repl.send(:inputrc_path)
  end

  # inputrc_path tests

  def test_inputrc_path_uses_inputrc_env_var
    inputrc_file = File.join(@tempdir, 'my_inputrc')
    File.write(inputrc_file, "# custom inputrc\n")
    ENV['INPUTRC'] = inputrc_file

    result = inputrc_path

    assert_equal inputrc_file, result
  end

  def test_inputrc_path_ignores_nonexistent_inputrc_env
    ENV['INPUTRC'] = '/nonexistent/inputrc/file'

    result = inputrc_path

    # Should fall through to other options (may be nil or home inputrc)
    assert_not_equal '/nonexistent/inputrc/file', result
  end

  def test_inputrc_path_ignores_empty_inputrc_env
    ENV['INPUTRC'] = ''

    result = inputrc_path

    # Should not return empty string
    assert_not_equal '', result
  end

  def test_inputrc_path_uses_home_inputrc_as_fallback
    # Create a fake home directory
    fake_home = File.join(@tempdir, 'home')
    FileUtils.mkdir_p(fake_home)
    home_inputrc = File.join(fake_home, '.inputrc')
    File.write(home_inputrc, "# home inputrc\n")

    ENV.delete('INPUTRC')
    ENV['HOME'] = fake_home

    result = inputrc_path

    assert_equal home_inputrc, result
  end

  def test_inputrc_path_uses_xdg_config_as_fallback
    # Create a fake home directory without .inputrc
    fake_home = File.join(@tempdir, 'home')
    FileUtils.mkdir_p(fake_home)

    # Create XDG config path
    xdg_config = File.join(@tempdir, 'xdg_config')
    xdg_inputrc_dir = File.join(xdg_config, 'readline')
    FileUtils.mkdir_p(xdg_inputrc_dir)
    xdg_inputrc = File.join(xdg_inputrc_dir, 'inputrc')
    File.write(xdg_inputrc, "# xdg inputrc\n")

    ENV.delete('INPUTRC')
    ENV['HOME'] = fake_home
    ENV['XDG_CONFIG_HOME'] = xdg_config

    result = inputrc_path

    assert_equal xdg_inputrc, result
  end

  def test_inputrc_path_returns_nil_when_no_inputrc_exists
    # Create a fake home directory without any inputrc files
    fake_home = File.join(@tempdir, 'empty_home')
    FileUtils.mkdir_p(fake_home)

    ENV.delete('INPUTRC')
    ENV['HOME'] = fake_home
    ENV['XDG_CONFIG_HOME'] = File.join(@tempdir, 'nonexistent_xdg')

    result = inputrc_path

    assert_nil result
  end

  def test_inputrc_env_takes_priority_over_home
    # Create both INPUTRC file and ~/.inputrc
    custom_inputrc = File.join(@tempdir, 'custom_inputrc')
    File.write(custom_inputrc, "# custom\n")

    fake_home = File.join(@tempdir, 'home')
    FileUtils.mkdir_p(fake_home)
    home_inputrc = File.join(fake_home, '.inputrc')
    File.write(home_inputrc, "# home\n")

    ENV['INPUTRC'] = custom_inputrc
    ENV['HOME'] = fake_home

    result = inputrc_path

    assert_equal custom_inputrc, result
  end

  def test_home_inputrc_takes_priority_over_xdg
    # Create both ~/.inputrc and XDG inputrc
    fake_home = File.join(@tempdir, 'home')
    FileUtils.mkdir_p(fake_home)
    home_inputrc = File.join(fake_home, '.inputrc')
    File.write(home_inputrc, "# home\n")

    xdg_config = File.join(@tempdir, 'xdg_config')
    xdg_inputrc_dir = File.join(xdg_config, 'readline')
    FileUtils.mkdir_p(xdg_inputrc_dir)
    xdg_inputrc = File.join(xdg_inputrc_dir, 'inputrc')
    File.write(xdg_inputrc, "# xdg\n")

    ENV.delete('INPUTRC')
    ENV['HOME'] = fake_home
    ENV['XDG_CONFIG_HOME'] = xdg_config

    result = inputrc_path

    assert_equal home_inputrc, result
  end

  # load_inputrc tests

  def test_load_inputrc_does_not_crash_with_nonexistent_file
    ENV['INPUTRC'] = '/nonexistent/file'

    # Should not raise
    assert_nothing_raised do
      @repl.send(:load_inputrc)
    end
  end

  def test_load_inputrc_does_not_crash_with_empty_env
    ENV.delete('INPUTRC')

    assert_nothing_raised do
      @repl.send(:load_inputrc)
    end
  end

  def test_load_inputrc_loads_valid_inputrc_file
    inputrc_file = File.join(@tempdir, 'test_inputrc')
    # Write a simple inputrc file with valid settings
    File.write(inputrc_file, <<~INPUTRC)
      # Test inputrc file
      set bell-style none
      set completion-ignore-case on
    INPUTRC
    ENV['INPUTRC'] = inputrc_file

    # Should load without error
    assert_nothing_raised do
      @repl.send(:load_inputrc)
    end
  end

  def test_load_inputrc_handles_invalid_inputrc_gracefully
    inputrc_file = File.join(@tempdir, 'bad_inputrc')
    # Write an inputrc file with potentially problematic content
    File.write(inputrc_file, <<~INPUTRC)
      # Inputrc with unknown settings
      set unknown-option-xyz true
    INPUTRC
    ENV['INPUTRC'] = inputrc_file

    # Should not crash
    assert_nothing_raised do
      @repl.send(:load_inputrc)
    end
  end

  # Integration with setup_reline

  def test_setup_reline_calls_load_inputrc
    inputrc_file = File.join(@tempdir, 'setup_test_inputrc')
    File.write(inputrc_file, "set bell-style none\n")
    ENV['INPUTRC'] = inputrc_file

    # Create a new REPL which will call setup_reline
    # This should not raise any errors
    assert_nothing_raised do
      # setup_reline is called implicitly, but we can call it explicitly
      @repl.send(:setup_reline)
    end
  end
end
