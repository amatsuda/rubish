# frozen_string_literal: true

require_relative 'test_helper'

class TestBASH_LOADABLES_PATH < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('bash_loadables_test')
    Dir.chdir(@tempdir)

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

  # BASH_LOADABLES_PATH as fallback for RUBISH_LOADABLES_PATH

  def test_bash_loadables_path_used_when_rubish_not_set
    builtin_file = File.join(@loadables_dir, 'bashcmd.rb')
    File.write(builtin_file, <<~RUBY)
      BASHCMD = ->(args) { puts "bash loadables path works"; true }
    RUBY

    ENV.delete('RUBISH_LOADABLES_PATH')
    ENV['BASH_LOADABLES_PATH'] = @loadables_dir
    result = Rubish::Builtins.run('enable', ['-f', 'bashcmd.rb', 'bashcmd'])
    assert_equal true, result
    assert Rubish::Builtins.builtin_exists?('bashcmd')
  end

  def test_bash_loadables_path_adds_rb_extension
    builtin_file = File.join(@loadables_dir, 'bashext.rb')
    File.write(builtin_file, <<~RUBY)
      BASHEXT = ->(args) { true }
    RUBY

    ENV.delete('RUBISH_LOADABLES_PATH')
    ENV['BASH_LOADABLES_PATH'] = @loadables_dir
    result = Rubish::Builtins.run('enable', ['-f', 'bashext', 'bashext'])
    assert_equal true, result
    assert Rubish::Builtins.builtin_exists?('bashext')
  end

  def test_bash_loadables_path_searches_multiple_paths
    dir1 = File.join(@tempdir, 'dir1')
    dir2 = File.join(@tempdir, 'dir2')
    FileUtils.mkdir_p(dir1)
    FileUtils.mkdir_p(dir2)

    builtin_file = File.join(dir2, 'multipath.rb')
    File.write(builtin_file, <<~RUBY)
      MULTIPATH = ->(args) { true }
    RUBY

    ENV.delete('RUBISH_LOADABLES_PATH')
    ENV['BASH_LOADABLES_PATH'] = "#{dir1}:#{dir2}"
    result = Rubish::Builtins.run('enable', ['-f', 'multipath', 'multipath'])
    assert_equal true, result
    assert Rubish::Builtins.builtin_exists?('multipath')
  end

  # RUBISH_LOADABLES_PATH takes precedence

  def test_rubish_loadables_path_takes_precedence
    rubish_dir = File.join(@tempdir, 'rubish_loadables')
    bash_dir = File.join(@tempdir, 'bash_loadables')
    FileUtils.mkdir_p(rubish_dir)
    FileUtils.mkdir_p(bash_dir)

    # Create file only in rubish_loadables
    builtin_file = File.join(rubish_dir, 'precedence.rb')
    File.write(builtin_file, <<~RUBY)
      PRECEDENCE = ->(args) { puts "from rubish"; true }
    RUBY

    ENV['RUBISH_LOADABLES_PATH'] = rubish_dir
    ENV['BASH_LOADABLES_PATH'] = bash_dir
    result = Rubish::Builtins.run('enable', ['-f', 'precedence', 'precedence'])
    assert_equal true, result, 'Should find in RUBISH_LOADABLES_PATH'
    assert Rubish::Builtins.builtin_exists?('precedence')
  end

  def test_both_paths_not_set
    ENV.delete('RUBISH_LOADABLES_PATH')
    ENV.delete('BASH_LOADABLES_PATH')

    output = capture_stdout do
      result = Rubish::Builtins.run('enable', ['-f', 'notfound.rb', 'notfound'])
      assert_equal false, result
    end
    assert_match(/cannot open/, output)
  end

  # Execute builtin loaded via BASH_LOADABLES_PATH

  def test_builtin_loaded_via_bash_path_executes
    builtin_file = File.join(@loadables_dir, 'execbash.rb')
    File.write(builtin_file, <<~RUBY)
      EXECBASH = ->(args) { puts "args: \#{args.join(',')}"; true }
    RUBY

    ENV.delete('RUBISH_LOADABLES_PATH')
    ENV['BASH_LOADABLES_PATH'] = @loadables_dir
    Rubish::Builtins.run('enable', ['-f', 'execbash', 'execbash'])

    output = capture_stdout do
      result = Rubish::Builtins.run('execbash', ['one', 'two'])
      assert_equal true, result
    end
    assert_equal "args: one,two\n", output
  end

  # Method-based builtins via BASH_LOADABLES_PATH

  def test_bash_path_loads_method_based_builtin
    builtin_file = File.join(@loadables_dir, 'bashmethod.rb')
    File.write(builtin_file, <<~RUBY)
      def self.run_bashmethod(args)
        puts "method via bash path"
        true
      end
    RUBY

    ENV.delete('RUBISH_LOADABLES_PATH')
    ENV['BASH_LOADABLES_PATH'] = @loadables_dir
    result = Rubish::Builtins.run('enable', ['-f', 'bashmethod', 'bashmethod'])
    assert_equal true, result
    assert Rubish::Builtins.builtin_exists?('bashmethod')
  end

  # Environment variable is readable

  def test_bash_loadables_path_readable
    @repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'output.txt')
    ENV['BASH_LOADABLES_PATH'] = '/test/path'
    @repl.send(:execute, "echo $BASH_LOADABLES_PATH > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '/test/path', content
  end

  def test_rubish_loadables_path_readable
    @repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'output.txt')
    ENV['RUBISH_LOADABLES_PATH'] = '/rubish/path'
    @repl.send(:execute, "echo $RUBISH_LOADABLES_PATH > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '/rubish/path', content
  end
end
