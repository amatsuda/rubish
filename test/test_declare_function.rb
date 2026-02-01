# frozen_string_literal: true

require_relative 'test_helper'

class TestDeclareFunction < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_declare_func_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Basic function definition

  def test_define_simple_function
    execute('hello() { echo hello; }')
    assert @repl.functions.key?('hello')
  end

  def test_define_function_with_keyword
    execute('function greet { echo greet; }')
    assert @repl.functions.key?('greet')
  end

  def test_function_stores_source
    execute('myfunc() { echo test; }')
    func_info = @repl.functions['myfunc']
    assert_not_nil func_info[:source_code]
  end

  # declare -f (show function definitions)

  def test_declare_f_shows_function_definition
    execute('testfn() { echo hello world; }')
    output = capture_stdout { Rubish::Builtins.declare(['-f', 'testfn']) }
    assert_match(/testfn\(\) \{/, output)
    assert_match(/echo hello world/, output)
    assert_match(/\}/, output)
  end

  def test_declare_f_all_functions
    execute('fn1() { echo one; }')
    execute('fn2() { echo two; }')
    output = capture_stdout { Rubish::Builtins.declare(['-f']) }
    assert_match(/fn1\(\) \{/, output)
    assert_match(/fn2\(\) \{/, output)
  end

  def test_declare_f_nonexistent_function
    output = capture_stdout { Rubish::Builtins.declare(['-f', 'nonexistent']) }
    assert_match(/not found/, output)
  end

  # declare -F (show function names only)

  def test_declare_F_shows_name_only
    execute('myfunc() { echo test; }')
    output = capture_stdout { Rubish::Builtins.declare(['-F', 'myfunc']) }
    assert_match(/declare -f myfunc/, output)
    # Should not show the body
    refute_match(/echo test/, output)
  end

  def test_declare_F_all_functions
    execute('fn1() { echo one; }')
    execute('fn2() { echo two; }')
    output = capture_stdout { Rubish::Builtins.declare(['-F']) }
    assert_match(/declare -f fn1/, output)
    assert_match(/declare -f fn2/, output)
    # Should not show bodies
    refute_match(/echo one/, output)
    refute_match(/echo two/, output)
  end

  def test_declare_F_nonexistent_function
    output = capture_stdout { Rubish::Builtins.declare(['-F', 'nonexistent']) }
    assert_match(/not found/, output)
  end

  # Function with complex body

  def test_function_with_if_statement
    execute('checkarg() { if [ -n "$1" ]; then echo yes; else echo no; fi; }')
    func_info = @repl.functions['checkarg']
    assert_not_nil func_info[:source_code]
    assert_match(/if/, func_info[:source_code])
  end

  def test_function_with_loop
    execute('countdown() { for i in 3 2 1; do echo $i; done; }')
    func_info = @repl.functions['countdown']
    assert_not_nil func_info[:source_code]
    assert_match(/for/, func_info[:source_code])
  end

  # function_lister and function_getter callbacks

  def test_function_lister_callback
    execute('fn1() { echo 1; }')
    execute('fn2() { echo 2; }')
    functions = Rubish::Builtins.current_state.function_lister.call
    assert functions.key?('fn1')
    assert functions.key?('fn2')
  end

  def test_function_getter_callback
    execute('myfn() { echo test; }')
    info = Rubish::Builtins.current_state.function_getter.call('myfn')
    assert_not_nil info
    assert info[:source]
  end

  def test_function_getter_returns_nil_for_nonexistent
    info = Rubish::Builtins.current_state.function_getter.call('nonexistent')
    assert_nil info
  end

  # Function checker and remover

  def test_function_checker
    execute('testfunc() { echo test; }')
    assert Rubish::Builtins.current_state.function_checker.call('testfunc')
    assert_false Rubish::Builtins.current_state.function_checker.call('nonexistent')
  end

  def test_function_remover
    execute('removeme() { echo remove; }')
    assert @repl.functions.key?('removeme')
    Rubish::Builtins.current_state.function_remover.call('removeme')
    assert_false @repl.functions.key?('removeme')
  end

  # Combined with unset -f

  def test_unset_f_removes_function
    execute('todelete() { echo delete; }')
    assert @repl.functions.key?('todelete')
    execute('unset -f todelete')
    assert_false @repl.functions.key?('todelete')
  end
end
