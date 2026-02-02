# frozen_string_literal: true

require_relative 'test_helper'

class TestLazyLoad < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_lazy_load_test')
    # Clear any pending lazy loads from previous tests
    Rubish::LazyLoader.clear! if defined?(Rubish::LazyLoader)
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::LazyLoader.clear! if defined?(Rubish::LazyLoader)
  end

  # === Lexer tests ===

  def test_lazy_load_keyword_tokenized
    tokens = Rubish::Lexer.new('lazy_load').tokenize
    assert_equal 1, tokens.length
    assert_equal :LAZY_LOAD, tokens.first.type
    assert_equal 'lazy_load', tokens.first.value
  end

  def test_lazy_load_with_braces_tokenized
    tokens = Rubish::Lexer.new('lazy_load { echo test }').tokenize
    types = tokens.map(&:type)
    assert_equal [:LAZY_LOAD, :LBRACE, :WORD, :WORD, :RBRACE], types
  end

  # === Parser tests ===

  def test_parser_produces_lazy_load_node
    tokens = Rubish::Lexer.new('lazy_load { echo test }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::LazyLoad, ast
    assert_not_nil ast.body
  end

  def test_parser_lazy_load_with_command
    tokens = Rubish::Lexer.new('lazy_load { ls -la }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::LazyLoad, ast
    assert_instance_of Rubish::AST::Command, ast.body
    assert_equal 'ls', ast.body.name
    assert_equal ['-la'], ast.body.args
  end

  def test_parser_lazy_load_with_pipeline
    tokens = Rubish::Lexer.new('lazy_load { echo foo | cat }').tokenize
    ast = Rubish::Parser.new(tokens).parse
    assert_instance_of Rubish::AST::LazyLoad, ast
    assert_instance_of Rubish::AST::Pipeline, ast.body
  end

  def test_parser_lazy_load_requires_braces
    tokens = Rubish::Lexer.new('lazy_load echo test').tokenize
    assert_raise(RuntimeError) do
      Rubish::Parser.new(tokens).parse
    end
  end

  # === Codegen tests ===

  def generate(input)
    tokens = Rubish::Lexer.new(input).tokenize
    ast = Rubish::Parser.new(tokens).parse
    Rubish::Codegen.new.generate(ast)
  end

  def test_codegen_lazy_load_simple
    code = generate('lazy_load { echo test }')
    assert_match(/__lazy_load \{/, code)
    assert_match(/__cmd\("echo"/, code)
  end

  def test_codegen_lazy_load_with_eval
    # eval "$(cmd)" pattern uses thread-safe __lazy_load_eval
    code = generate('lazy_load { eval "$(echo export FOO=bar)" }')
    assert_match(/__lazy_load_eval\("echo export FOO=bar"\)/, code)
  end

  def test_codegen_lazy_load_generic
    # Non-eval patterns fall back to generic __lazy_load
    code = generate('lazy_load { echo test }')
    assert_match(/__lazy_load \{/, code)
    assert_match(/__cmd\("echo"/, code)
  end

  # === LazyLoader module tests ===

  def test_lazy_loader_register_creates_task
    require_relative '../lib/rubish/lazy_loader'

    initial_pending = Rubish::LazyLoader.pending?

    executor = ->(code) { @repl.send(:execute, code) }
    Rubish::LazyLoader.register('test-task', executor) do
      'echo hello'
    end

    # Task should be pending immediately after registration
    assert Rubish::LazyLoader.pending?
  end

  def test_lazy_loader_wait_all_completes_tasks
    require_relative '../lib/rubish/lazy_loader'

    executor = ->(code) { @repl.send(:execute, code) }
    Rubish::LazyLoader.register('test-wait', executor) do
      sleep 0.01
      'export LAZY_VAR=worked'
    end

    # Wait for completion
    Rubish::LazyLoader.wait_all(executor, timeout: 5)

    # The executor should have been called with the shell code
    assert_equal 'worked', ENV['LAZY_VAR']
  end

  def test_lazy_loader_apply_completed_returns_applied_names
    require_relative '../lib/rubish/lazy_loader'

    executor = ->(code) { @repl.send(:execute, code) }
    Rubish::LazyLoader.register('apply-test', executor) do
      'export APPLIED=yes'
    end

    # Wait for thread to complete
    Rubish::LazyLoader.wait_all(executor, timeout: 5)

    assert_equal 'yes', ENV['APPLIED']
  end

  def test_lazy_loader_handles_empty_result
    require_relative '../lib/rubish/lazy_loader'

    executor = ->(code) { @repl.send(:execute, code) }
    Rubish::LazyLoader.register('empty-result', executor) do
      ''  # Empty result should not cause errors
    end

    # Should complete without error
    Rubish::LazyLoader.wait_all(executor, timeout: 5)

    assert_false Rubish::LazyLoader.pending?
  end

  def test_lazy_loader_handles_nil_result
    require_relative '../lib/rubish/lazy_loader'

    executor = ->(code) { @repl.send(:execute, code) }
    Rubish::LazyLoader.register('nil-result', executor) do
      nil
    end

    # Should complete without error
    Rubish::LazyLoader.wait_all(executor, timeout: 5)

    assert_false Rubish::LazyLoader.pending?
  end

  def test_lazy_loader_status_shows_task_info
    require_relative '../lib/rubish/lazy_loader'

    executor = ->(code) { @repl.send(:execute, code) }
    Rubish::LazyLoader.register('status-test', executor) do
      sleep 0.1
      'echo done'
    end

    status = Rubish::LazyLoader.status
    assert_equal 1, status.length
    assert_equal 'status-test', status.first[:name]

    Rubish::LazyLoader.wait_all(executor, timeout: 5)
  end

  def test_lazy_loader_handles_errors_gracefully
    require_relative '../lib/rubish/lazy_loader'

    executor = ->(code) { @repl.send(:execute, code) }
    Rubish::LazyLoader.register('error-test', executor) do
      raise 'intentional error for testing'
    end

    # Should not raise, error is captured
    error_output = capture_stderr do
      Rubish::LazyLoader.wait_all(executor, timeout: 5)
    end

    assert_match(/intentional error/, error_output)
  end

  def test_lazy_loader_clear_removes_all_tasks
    require_relative '../lib/rubish/lazy_loader'

    executor = ->(code) { }
    Rubish::LazyLoader.register('clear-test', executor) { 'echo test' }

    assert Rubish::LazyLoader.pending?

    Rubish::LazyLoader.clear!

    # After clear, status should be empty
    assert_empty Rubish::LazyLoader.status
  end

  # === Integration tests ===

  def test_lazy_load_with_eval_export
    # lazy_load is designed to work with eval "$(cmd)" pattern
    # The command substitution runs in background thread, result is eval'd in main thread
    execute('lazy_load { eval "$(echo export LAZY_EXPORT=integration_test)" }')

    # Wait for lazy loads to complete
    Rubish::LazyLoader.wait_all(->(code) { execute(code) }, timeout: 5)

    # Verify export was applied
    assert_equal 'integration_test', ENV['LAZY_EXPORT']
  end

  def test_lazy_load_with_eval_function_definition
    # Define a function via lazy_load using eval
    execute('lazy_load { eval "$(echo \'my_lazy_func() { echo lazy_func_works; }\')" }')

    # Wait for completion
    Rubish::LazyLoader.wait_all(->(code) { execute(code) }, timeout: 5)

    # Call the function
    output = capture_stdout { execute('my_lazy_func') }
    assert_equal "lazy_func_works\n", output
  end

  def test_lazy_load_with_eval_alias
    execute('lazy_load { eval "$(echo \'alias ll=\"ls -la\"\')" }')

    Rubish::LazyLoader.wait_all(->(code) { execute(code) }, timeout: 5)

    # Verify alias was set
    assert Rubish::Builtins.current_state.aliases.key?('ll')
  end

  def test_lazy_load_multiline_from_source
    # Multi-line lazy_load blocks should work when sourced from files
    content = <<~SHELL
      lazy_load {
        eval "$(echo export MULTILINE_SOURCE_TEST=works)"
      }
    SHELL
    File.write("#{@tempdir}/multiline.sh", content)

    Rubish::Builtins.source(["#{@tempdir}/multiline.sh"])
    Rubish::LazyLoader.wait_all(->(code) { execute(code) }, timeout: 5)

    assert_equal 'works', ENV['MULTILINE_SOURCE_TEST']
  end

  def test_multiple_lazy_loads_run_in_parallel
    require_relative '../lib/rubish/lazy_loader'

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Register multiple lazy loads that each take some time
    # Use echo commands that return shell code to be eval'd
    execute('lazy_load { eval "$(sleep 0.1; echo export LAZY1=done)" }')
    execute('lazy_load { eval "$(sleep 0.1; echo export LAZY2=done)" }')
    execute('lazy_load { eval "$(sleep 0.1; echo export LAZY3=done)" }')

    Rubish::LazyLoader.wait_all(->(code) { execute(code) }, timeout: 5)

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    # If parallel, should take ~0.1s, not 0.3s
    # Allow generous overhead for CI environments
    assert elapsed < 0.25, "Expected parallel execution (<0.25s), got #{elapsed}s"

    assert_equal 'done', ENV['LAZY1']
    assert_equal 'done', ENV['LAZY2']
    assert_equal 'done', ENV['LAZY3']
  end
end
