# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Assigning to a readonly variable fails with status 1 and leaves the value,
# whether the assignment is a lone statement or part of a command list
class TestReadonlyEnforcement < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @name = "ro_#{rand(1_000_000)}"
  end

  def run_and_read(script)
    Dir.mktmpdir('rubish_ro') do |dir|
      out = File.join(dir, 'out.txt')
      execute("#{script} > #{out}")
      File.read(out)
    end
  end

  def test_lone_assignment_to_readonly_scalar_is_refused
    execute("readonly #{@name}=first")
    # fatal outside an interactive shell, with status 1 (bash)
    err = capture_stderr { @status = catch(:exit) { execute("#{@name}=second") } }
    assert_match(/#{@name}: readonly variable/, err)
    assert_equal 1, @status
    assert_equal "first\n", run_and_read("echo $#{@name}")
  end

  def test_assignment_in_a_list_to_readonly_scalar_is_refused
    execute("readonly #{@name}=first")
    err = capture_stderr { catch(:exit) { execute("#{@name}=second; true") } }
    assert_match(/#{@name}: readonly variable/, err)
    assert_equal "first\n", run_and_read("echo $#{@name}")
  end

  def test_readonly_array_element_assignment_is_refused
    execute("#{@name}=(a b)")
    execute("readonly #{@name}")
    err = capture_stderr { catch(:exit) { execute("#{@name}[0]=c") } }
    assert_match(/#{@name}: readonly variable/, err)
    assert_equal "a b\n", run_and_read("echo \"${#{@name}[@]}\"")
  end

  def test_readonly_compound_reassignment_is_refused
    execute("#{@name}=(a b)")
    execute("readonly #{@name}")
    err = capture_stderr { catch(:exit) { execute("#{@name}=(x)") } }
    assert_match(/#{@name}: readonly variable/, err)
    assert_equal "a b\n", run_and_read("echo \"${#{@name}[@]}\"")
  end

  def test_declare_on_readonly_is_refused
    execute("readonly #{@name}=first")
    err = capture_stderr { execute("declare #{@name}=second") }
    assert_match(/readonly variable/, err)
    assert_equal "first\n", run_and_read("echo $#{@name}")
  end

  def test_export_on_readonly_is_refused
    execute("readonly #{@name}=first")
    err = capture_stderr { execute("export #{@name}=second") }
    assert_match(/readonly variable/, err)
    assert_equal "first\n", run_and_read("echo $#{@name}")
  end
end
