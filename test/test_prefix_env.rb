# frozen_string_literal: true

require_relative 'test_helper'

class TestPrefixEnv < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_prefix_env_test')
    @saved_env = ENV.to_h
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @saved_env.each { |k, v| ENV[k] = v }
  end

  def generate(input)
    tokens = Rubish::Lexer.new(input).tokenize
    ast = Rubish::Parser.new(tokens).parse
    Rubish::Codegen.new.generate(ast)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Code generation tests

  def test_codegen_simple_prefix_env
    code = generate('FOO=hello printenv FOO')
    assert_match(/__prefix_env: \{"FOO" => "hello"\}/, code)
    assert_match(/__cmd\("printenv"/, code)
  end

  def test_codegen_multiple_prefix_env
    code = generate('FOO=hello BAR=world printenv')
    assert_match(/__prefix_env: \{"FOO" => "hello", "BAR" => "world"\}/, code)
  end

  def test_codegen_prefix_env_with_args
    code = generate('FOO=bar echo hello')
    assert_match(/__prefix_env: \{"FOO" => "bar"\}/, code)
    assert_match(/"hello"/, code)
  end

  def test_codegen_bare_assignment_no_prefix_env
    # Bare assignment should not generate __prefix_env
    code = generate('FOO=hello')
    refute_match(/__prefix_env/, code)
  end

  # Execution tests

  def test_prefix_env_simple
    execute("FOO=hello printenv FOO > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_prefix_env_multiple_vars
    execute("FOO=hello BAR=world sh -c 'echo $FOO $BAR' > #{output_file}")
    assert_equal "hello world\n", File.read(output_file)
  end

  def test_prefix_env_does_not_leak
    ENV.delete('PREFIX_TEST')
    execute("PREFIX_TEST=leaked echo ignored > #{output_file}")
    assert_nil ENV['PREFIX_TEST']
  end

  def test_prefix_env_in_pipeline
    execute("FOO=hello printenv FOO | cat > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_prefix_env_override_existing
    ENV['OVERRIDE_ME'] = 'original'
    execute("OVERRIDE_ME=overridden printenv OVERRIDE_ME > #{output_file}")
    assert_equal "overridden\n", File.read(output_file)
    # Original value should be preserved in shell
    assert_equal 'original', ENV['OVERRIDE_ME']
  end

  def test_prefix_env_empty_value
    execute("EMPTY= printenv EMPTY > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  def test_bare_assignment_still_works
    execute('BARE_ASSIGN=value')
    assert_equal 'value', ENV['BARE_ASSIGN']
  end

  def test_multiple_bare_assignments
    execute('A=1 B=2 C=3')
    assert_equal '1', ENV['A']
    assert_equal '2', ENV['B']
    assert_equal '3', ENV['C']
  end

  def test_prefix_env_with_variable_expansion
    ENV['EXPANDED'] = 'expanded_value'
    execute("RESULT=$EXPANDED printenv RESULT > #{output_file}")
    assert_equal "expanded_value\n", File.read(output_file)
  end
end
