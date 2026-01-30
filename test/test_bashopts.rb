# frozen_string_literal: true

require_relative 'test_helper'

class TestBASHOPTS < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_bashopts_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASHOPTS functionality

  def test_bashopts_returns_colon_separated_list
    value = Rubish::Builtins.bashopts
    assert_kind_of String, value
    # Should contain options separated by colons
    assert value.include?(':') || value.length > 0
  end

  def test_bashopts_contains_enabled_options
    # cmdhist is enabled by default
    value = Rubish::Builtins.bashopts
    assert value.split(':').include?('cmdhist'), 'BASHOPTS should contain cmdhist (enabled by default)'
  end

  def test_bashopts_equals_rubishopts
    bashopts = Rubish::Builtins.bashopts
    rubishopts = Rubish::Builtins.rubishopts
    assert_equal rubishopts, bashopts, 'BASHOPTS should equal RUBISHOPTS'
  end

  def test_bashopts_via_variable_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASHOPTS > #{output_file}")
    content = File.read(output_file).strip
    assert content.length > 0
    assert content.include?(':'), 'BASHOPTS should contain colon separators'
  end

  def test_bashopts_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASHOPTS} > #{output_file}")
    content = File.read(output_file).strip
    assert content.length > 0
  end

  # BASHOPTS reflects shopt changes

  def test_bashopts_reflects_shopt_enable
    execute('shopt -s dotglob')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASHOPTS > #{output_file}")
    content = File.read(output_file).strip
    assert content.split(':').include?('dotglob'), 'BASHOPTS should include dotglob after shopt -s'
    execute('shopt -u dotglob')
  end

  def test_bashopts_reflects_shopt_disable
    execute('shopt -s dotglob')
    execute('shopt -u dotglob')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASHOPTS > #{output_file}")
    content = File.read(output_file).strip
    assert_false content.split(':').include?('dotglob'), 'BASHOPTS should not include dotglob after shopt -u'
  end

  def test_bashopts_multiple_options
    execute('shopt -s dotglob')
    execute('shopt -s nullglob')
    execute('shopt -s extglob')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASHOPTS > #{output_file}")
    content = File.read(output_file).strip
    options = content.split(':')
    assert options.include?('dotglob')
    assert options.include?('nullglob')
    assert options.include?('extglob')
    execute('shopt -u dotglob')
    execute('shopt -u nullglob')
    execute('shopt -u extglob')
  end

  # BASHOPTS is read-only

  def test_bashopts_assignment_ignored
    original = Rubish::Builtins.bashopts
    execute('BASHOPTS=something')
    # BASHOPTS should still reflect actual options, not the assigned value
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASHOPTS > #{output_file}")
    content = File.read(output_file).strip
    # Should still contain actual options
    assert content.include?(':') || content.include?('cmdhist')
  end

  # BASHOPTS is sorted alphabetically

  def test_bashopts_is_sorted
    value = Rubish::Builtins.bashopts
    options = value.split(':')
    sorted_options = options.sort
    assert_equal sorted_options, options, 'BASHOPTS should be sorted alphabetically'
  end

  # Parameter expansion

  def test_bashopts_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASHOPTS:-default} > #{output_file}")
    content = File.read(output_file).strip
    # Should not be 'default' since BASHOPTS is always set
    assert_not_equal 'default', content
  end

  def test_bashopts_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASHOPTS:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'BASHOPTS should be considered set'
  end

  # BASHOPTS in conditional

  def test_bashopts_in_conditional
    output_file = File.join(@tempdir, 'output.txt')
    execute('if [ -n "$BASHOPTS" ]; then echo set; else echo empty; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'set', content
  end

  # Check specific default options

  def test_bashopts_default_options_enabled
    value = Rubish::Builtins.bashopts
    options = value.split(':')
    # These are enabled by default
    assert options.include?('cmdhist'), 'cmdhist should be enabled by default'
    assert options.include?('expand_aliases'), 'expand_aliases should be enabled by default'
    assert options.include?('extquote'), 'extquote should be enabled by default'
    assert options.include?('interactive_comments'), 'interactive_comments should be enabled by default'
    assert options.include?('progcomp'), 'progcomp should be enabled by default'
    assert options.include?('promptvars'), 'promptvars should be enabled by default'
    assert options.include?('sourcepath'), 'sourcepath should be enabled by default'
  end

  def test_bashopts_default_options_disabled
    value = Rubish::Builtins.bashopts
    options = value.split(':')
    # These are disabled by default
    assert_false options.include?('dotglob'), 'dotglob should be disabled by default'
    assert_false options.include?('nullglob'), 'nullglob should be disabled by default'
    assert_false options.include?('failglob'), 'failglob should be disabled by default'
    assert_false options.include?('globstar'), 'globstar should be disabled by default'
  end

  # BASHOPTS substring operations

  def test_bashopts_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASHOPTS} > #{output_file}")
    length = File.read(output_file).strip.to_i
    assert length > 0, 'BASHOPTS length should be greater than 0'
  end

  # BASHOPTS in double quotes

  def test_bashopts_in_double_quotes
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"BASHOPTS=$BASHOPTS\" > #{output_file}")
    content = File.read(output_file).strip
    assert content.start_with?('BASHOPTS=')
    assert content.include?(':')
  end
end
