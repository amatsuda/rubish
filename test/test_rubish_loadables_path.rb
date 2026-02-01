# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_LOADABLES_PATH < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_loadables_test')
    Dir.chdir(@tempdir)

    # Create REPL to initialize context (needed for Builtins calls)
    @repl = Rubish::REPL.new

    # Create a loadables directory
    @loadables_dir = File.join(@tempdir, 'loadables')
    FileUtils.mkdir_p(@loadables_dir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }

    # Clean up any loaded builtins
    Rubish::Builtins.loaded_builtins.keys.each do |name|
      Rubish::Builtins.loaded_builtins.delete(name)
    end
    # Clear dynamic commands
    Rubish::Builtins.instance_variable_get(:@dynamic_commands).clear
  end

  # Basic loading functionality

  def test_enable_f_loads_builtin_from_absolute_path
    builtin_file = File.join(@tempdir, 'mybuiltin.rb')
    File.write(builtin_file, <<~RUBY)
      MYBUILTIN = ->(args) { puts "mybuiltin: \#{args.join(' ')}"; true }
    RUBY

    result = Rubish::Builtins.run('enable', ['-f', builtin_file, 'mybuiltin'])
    assert_equal true, result
    assert Rubish::Builtins.builtin_exists?('mybuiltin')
    assert Rubish::Builtins.loaded_builtins.key?('mybuiltin')
  end

  def test_enable_f_loads_builtin_from_rubish_loadables_path
    builtin_file = File.join(@loadables_dir, 'testcmd.rb')
    File.write(builtin_file, <<~RUBY)
      TESTCMD = ->(args) { puts "test command"; true }
    RUBY

    ENV['RUBISH_LOADABLES_PATH'] = @loadables_dir
    result = Rubish::Builtins.run('enable', ['-f', 'testcmd.rb', 'testcmd'])
    assert_equal true, result
    assert Rubish::Builtins.builtin_exists?('testcmd')
  end

  def test_enable_f_adds_rb_extension
    builtin_file = File.join(@loadables_dir, 'addext.rb')
    File.write(builtin_file, <<~RUBY)
      ADDEXT = ->(args) { true }
    RUBY

    ENV['RUBISH_LOADABLES_PATH'] = @loadables_dir
    result = Rubish::Builtins.run('enable', ['-f', 'addext', 'addext'])
    assert_equal true, result
    assert Rubish::Builtins.builtin_exists?('addext')
  end

  def test_enable_f_searches_multiple_paths
    dir1 = File.join(@tempdir, 'dir1')
    dir2 = File.join(@tempdir, 'dir2')
    FileUtils.mkdir_p(dir1)
    FileUtils.mkdir_p(dir2)

    builtin_file = File.join(dir2, 'indir2.rb')
    File.write(builtin_file, <<~RUBY)
      INDIR2 = ->(args) { true }
    RUBY

    ENV['RUBISH_LOADABLES_PATH'] = "#{dir1}:#{dir2}"
    result = Rubish::Builtins.run('enable', ['-f', 'indir2', 'indir2'])
    assert_equal true, result
    assert Rubish::Builtins.builtin_exists?('indir2')
  end

  def test_enable_f_file_not_found
    ENV['RUBISH_LOADABLES_PATH'] = @loadables_dir
    output = capture_stdout do
      result = Rubish::Builtins.run('enable', ['-f', 'nonexistent.rb', 'nonexistent'])
      assert_equal false, result
    end
    assert_match(/cannot open/, output)
  end

  def test_enable_f_builtin_not_found_in_file
    builtin_file = File.join(@loadables_dir, 'empty.rb')
    File.write(builtin_file, <<~RUBY)
      # No builtins defined
    RUBY

    ENV['RUBISH_LOADABLES_PATH'] = @loadables_dir
    output = capture_stdout do
      result = Rubish::Builtins.run('enable', ['-f', 'empty.rb', 'missing'])
      assert_equal false, result
    end
    assert_match(/not found in/, output)
  end

  # Method-based builtins

  def test_enable_f_loads_method_based_builtin
    builtin_file = File.join(@tempdir, 'methodbuiltin.rb')
    File.write(builtin_file, <<~RUBY)
      def self.run_mymethod(args)
        puts "method builtin: \#{args.join(' ')}"
        true
      end
    RUBY

    result = Rubish::Builtins.run('enable', ['-f', builtin_file, 'mymethod'])
    assert_equal true, result
    assert Rubish::Builtins.builtin_exists?('mymethod')
  end

  # Executing loaded builtins

  def test_loaded_builtin_executes
    builtin_file = File.join(@tempdir, 'exectest.rb')
    File.write(builtin_file, <<~RUBY)
      EXECTEST = ->(args) { puts "executed with: \#{args.join(',')}"; true }
    RUBY

    Rubish::Builtins.run('enable', ['-f', builtin_file, 'exectest'])

    output = capture_stdout do
      result = Rubish::Builtins.run('exectest', ['arg1', 'arg2'])
      assert_equal true, result
    end
    assert_equal "executed with: arg1,arg2\n", output
  end

  def test_loaded_builtin_returns_false
    builtin_file = File.join(@tempdir, 'failtest.rb')
    File.write(builtin_file, <<~RUBY)
      FAILTEST = ->(args) { false }
    RUBY

    Rubish::Builtins.run('enable', ['-f', builtin_file, 'failtest'])
    result = Rubish::Builtins.run('failtest', [])
    assert_equal false, result
  end

  # Deleting loaded builtins

  def test_enable_d_deletes_loaded_builtin
    builtin_file = File.join(@tempdir, 'deleteme.rb')
    File.write(builtin_file, <<~RUBY)
      DELETEME = ->(args) { true }
    RUBY

    Rubish::Builtins.run('enable', ['-f', builtin_file, 'deleteme'])
    assert Rubish::Builtins.builtin_exists?('deleteme')

    result = Rubish::Builtins.run('enable', ['-d', 'deleteme'])
    assert_equal true, result
    refute Rubish::Builtins.builtin_exists?('deleteme')
    refute Rubish::Builtins.loaded_builtins.key?('deleteme')
  end

  def test_enable_d_fails_for_static_builtin
    output = capture_stdout do
      result = Rubish::Builtins.run('enable', ['-d', 'cd'])
      assert_equal false, result
    end
    assert_match(/not a dynamically loaded builtin/, output)
  end

  def test_enable_d_fails_for_unknown_builtin
    output = capture_stdout do
      result = Rubish::Builtins.run('enable', ['-d', 'unknownbuiltin'])
      assert_equal false, result
    end
    assert_match(/not a dynamically loaded builtin/, output)
  end

  # Option parsing

  def test_enable_f_requires_argument
    output = capture_stdout do
      result = Rubish::Builtins.run('enable', ['-f'])
      assert_equal false, result
    end
    assert_match(/option requires an argument/, output)
  end

  def test_enable_f_combined_option_format
    builtin_file = File.join(@tempdir, 'combined.rb')
    File.write(builtin_file, <<~RUBY)
      COMBINED = ->(args) { true }
    RUBY

    # Test -f with filename attached: -fcombined.rb
    result = Rubish::Builtins.run('enable', ["-f#{builtin_file}", 'combined'])
    assert_equal true, result
    assert Rubish::Builtins.builtin_exists?('combined')
  end

  # Integration with builtin? and type

  def test_loaded_builtin_is_recognized_as_builtin
    builtin_file = File.join(@tempdir, 'recognizable.rb')
    File.write(builtin_file, <<~RUBY)
      RECOGNIZABLE = ->(args) { true }
    RUBY

    Rubish::Builtins.run('enable', ['-f', builtin_file, 'recognizable'])
    assert Rubish::Builtins.builtin?('recognizable')
    assert Rubish::Builtins.builtin_exists?('recognizable')
    assert Rubish::Builtins.builtin_enabled?('recognizable')
  end

  def test_deleted_builtin_is_not_recognized
    builtin_file = File.join(@tempdir, 'tempbuiltin.rb')
    File.write(builtin_file, <<~RUBY)
      TEMPBUILTIN = ->(args) { true }
    RUBY

    Rubish::Builtins.run('enable', ['-f', builtin_file, 'tempbuiltin'])
    Rubish::Builtins.run('enable', ['-d', 'tempbuiltin'])

    refute Rubish::Builtins.builtin?('tempbuiltin')
    refute Rubish::Builtins.builtin_exists?('tempbuiltin')
  end

  # Error handling

  def test_enable_f_handles_syntax_error
    builtin_file = File.join(@tempdir, 'syntaxerror.rb')
    File.write(builtin_file, 'def broken(')

    output = capture_stdout do
      result = Rubish::Builtins.run('enable', ['-f', builtin_file, 'broken'])
      assert_equal false, result
    end
    assert_match(/syntaxerror\.rb/, output)
  end

  def test_enable_f_handles_runtime_error
    builtin_file = File.join(@tempdir, 'runtimeerror.rb')
    File.write(builtin_file, 'raise "test error"')

    output = capture_stdout do
      result = Rubish::Builtins.run('enable', ['-f', builtin_file, 'broken'])
      assert_equal false, result
    end
    assert_match(/test error/, output)
  end
end
