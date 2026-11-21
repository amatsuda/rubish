# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# With `shopt -s extglob`, `@(a|b)`, `+(x)`, `*(x)`, `?(x)` and `!(x)` are
# single pattern words, usable in case patterns and in filename globbing
class TestExtglobWords < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    execute('shopt -s extglob')
  end

  def teardown
    execute('shopt -u extglob')
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_extglob') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_alternation_in_case_pattern
    assert_equal "match\n", run_and_read('case foo.txt in *.@(txt|md)) echo match;; *) echo no;; esac')
    assert_equal "no\n", run_and_read('case foo.rb in *.@(txt|md)) echo match;; *) echo no;; esac')
  end

  def test_one_or_more_in_case_pattern
    assert_equal "match\n", run_and_read('case abc in +([a-c])) echo match;; *) echo no;; esac')
    assert_equal "no\n", run_and_read('case abd in +([a-c])) echo match;; *) echo no;; esac')
  end

  def test_negation_in_case_pattern
    assert_equal "other\n", run_and_read('case y in !(x)) echo other;; *) echo x;; esac')
    assert_equal "x\n", run_and_read('case x in !(x)) echo other;; *) echo x;; esac')
  end

  def test_extglob_filename_expansion
    original_dir = Dir.pwd
    Dir.mktmpdir('rubish_extglob_files') do |dir|
      %w[a.txt b.md c.rb].each { |f| File.write(File.join(dir, f), '') }
      execute("cd #{dir}")
      assert_equal "a.txt b.md\n", run_and_read('echo *.@(txt|md)')
      assert_equal "c.rb\n", run_and_read('echo !(*.txt|*.md)')
    ensure
      execute("cd #{original_dir}")
    end
  end
  def test_extglob_with_directory_prefix
    Dir.mktmpdir('rubish_extglob_dir') do |dir|
      %w[job.rb command.rb other.rb].each { |f| File.write(File.join(dir, f), '') }
      assert_equal "#{dir}/command.rb #{dir}/job.rb\n", run_and_read("echo #{dir}/@(job|command).rb")
    end
  end
end
