# frozen_string_literal: true

require_relative 'test_helper'

class TestParamTransform < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_transform_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # ${var@Q} - Quote for reuse as input
  def test_transform_q_basic
    ENV['TEST'] = 'hello'
    execute("echo ${TEST@Q} > #{output_file}")
    assert_equal "'hello'\n", File.read(output_file)
  end

  def test_transform_q_with_spaces
    ENV['TEST'] = 'hello world'
    execute("echo ${TEST@Q} > #{output_file}")
    assert_equal "'hello world'\n", File.read(output_file)
  end

  def test_transform_q_with_single_quote
    ENV['TEST'] = "it's a test"
    execute("echo ${TEST@Q} > #{output_file}")
    assert_equal "'it'\\''s a test'\n", File.read(output_file)
  end

  def test_transform_q_unset
    ENV.delete('UNSET_VAR')
    execute("echo ${UNSET_VAR@Q} > #{output_file}")
    assert_equal "''\n", File.read(output_file)
  end

  def test_transform_q_empty
    ENV['TEST'] = ''
    execute("echo ${TEST@Q} > #{output_file}")
    assert_equal "''\n", File.read(output_file)
  end

  # ${var@U} - Uppercase entire value
  def test_transform_u_upper_basic
    ENV['TEST'] = 'hello'
    execute("echo ${TEST@U} > #{output_file}")
    assert_equal "HELLO\n", File.read(output_file)
  end

  def test_transform_u_upper_mixed
    ENV['TEST'] = 'Hello World'
    execute("echo ${TEST@U} > #{output_file}")
    assert_equal "HELLO WORLD\n", File.read(output_file)
  end

  def test_transform_u_upper_already_upper
    ENV['TEST'] = 'HELLO'
    execute("echo ${TEST@U} > #{output_file}")
    assert_equal "HELLO\n", File.read(output_file)
  end

  def test_transform_u_upper_unset
    ENV.delete('UNSET_VAR')
    execute("echo ${UNSET_VAR@U} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  # ${var@u} - Uppercase first character
  def test_transform_u_first_basic
    ENV['TEST'] = 'hello'
    execute("echo ${TEST@u} > #{output_file}")
    assert_equal "Hello\n", File.read(output_file)
  end

  def test_transform_u_first_already_upper
    ENV['TEST'] = 'Hello'
    execute("echo ${TEST@u} > #{output_file}")
    assert_equal "Hello\n", File.read(output_file)
  end

  def test_transform_u_first_empty
    ENV['TEST'] = ''
    execute("echo ${TEST@u} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  # ${var@L} - Lowercase entire value
  def test_transform_l_basic
    ENV['TEST'] = 'HELLO'
    execute("echo ${TEST@L} > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_transform_l_mixed
    ENV['TEST'] = 'Hello World'
    execute("echo ${TEST@L} > #{output_file}")
    assert_equal "hello world\n", File.read(output_file)
  end

  def test_transform_l_already_lower
    ENV['TEST'] = 'hello'
    execute("echo ${TEST@L} > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_transform_l_unset
    ENV.delete('UNSET_VAR')
    execute("echo ${UNSET_VAR@L} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  # ${var@E} - Expand escape sequences
  def test_transform_e_newline
    ENV['TEST'] = 'hello\nworld'
    execute("echo ${TEST@E} > #{output_file}")
    assert_equal "hello\nworld\n", File.read(output_file)
  end

  def test_transform_e_tab
    ENV['TEST'] = 'hello\tworld'
    execute("echo ${TEST@E} > #{output_file}")
    assert_equal "hello\tworld\n", File.read(output_file)
  end

  def test_transform_e_no_escapes
    ENV['TEST'] = 'hello world'
    execute("echo ${TEST@E} > #{output_file}")
    assert_equal "hello world\n", File.read(output_file)
  end

  def test_transform_e_unset
    ENV.delete('UNSET_VAR')
    execute("echo ${UNSET_VAR@E} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  # ${var@A} - Assignment statement form
  def test_transform_a_upper_basic
    ENV['TEST'] = 'hello'
    Rubish::Builtins.instance_variable_get(:@var_attributes).delete('TEST')
    execute("echo ${TEST@A} > #{output_file}")
    assert_equal "declare -- TEST='hello'\n", File.read(output_file)
  end

  def test_transform_a_upper_with_spaces
    ENV['TEST'] = 'hello world'
    Rubish::Builtins.instance_variable_get(:@var_attributes).delete('TEST')
    execute("echo ${TEST@A} > #{output_file}")
    assert_equal "declare -- TEST='hello world'\n", File.read(output_file)
  end

  def test_transform_a_upper_exported
    ENV['TEST'] = 'hello'
    Rubish::Builtins.mark_exported('TEST')
    execute("echo ${TEST@A} > #{output_file}")
    assert_equal "declare -x TEST='hello'\n", File.read(output_file)
    # Clean up
    Rubish::Builtins.instance_variable_get(:@var_attributes).delete('TEST')
  end

  def test_transform_a_upper_unset
    ENV.delete('UNSET_VAR')
    execute("echo ${UNSET_VAR@A} > #{output_file}")
    assert_equal "declare -- UNSET_VAR\n", File.read(output_file)
  end

  # ${var@a} - Attribute flags
  def test_transform_a_lower_no_attrs
    ENV['TEST'] = 'hello'
    Rubish::Builtins.instance_variable_get(:@var_attributes).delete('TEST')
    execute("echo ${TEST@a} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  def test_transform_a_lower_exported
    ENV['TEST'] = 'hello'
    Rubish::Builtins.instance_variable_get(:@var_attributes)['TEST'] = Set.new([:export])
    execute("echo ${TEST@a} > #{output_file}")
    assert_equal "x\n", File.read(output_file)
    # Clean up
    Rubish::Builtins.instance_variable_get(:@var_attributes).delete('TEST')
  end

  def test_transform_a_lower_readonly
    ENV['TEST'] = 'hello'
    Rubish::Builtins.run('readonly', ['TEST'])
    execute("echo ${TEST@a} > #{output_file}")
    assert_equal "r\n", File.read(output_file)
    # Clean up
    Rubish::Builtins.clear_readonly_vars
  end

  # ${var@P} - Prompt expansion
  def test_transform_p_username
    ENV['TEST'] = '\u'
    execute("echo ${TEST@P} > #{output_file}")
    # The result should be the current username
    assert_equal "#{Etc.getlogin}\n", File.read(output_file)
  end

  def test_transform_p_hostname
    ENV['TEST'] = '\h'
    execute("echo ${TEST@P} > #{output_file}")
    # The result should be the hostname (short form)
    expected = Socket.gethostname.split('.').first
    assert_equal "#{expected}\n", File.read(output_file)
  end

  def test_transform_p_plain_text
    ENV['TEST'] = 'hello'
    execute("echo ${TEST@P} > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  # ${var@K} - Key-value pairs (for regular vars, same as @Q)
  def test_transform_k_basic
    ENV['TEST'] = 'hello'
    execute("echo ${TEST@K} > #{output_file}")
    assert_equal "'hello'\n", File.read(output_file)
  end

  def test_transform_k_unset
    ENV.delete('UNSET_VAR')
    execute("echo ${UNSET_VAR@K} > #{output_file}")
    assert_equal "''\n", File.read(output_file)
  end
end
