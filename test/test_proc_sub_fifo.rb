# frozen_string_literal: true

require_relative 'test_helper'

# Process substitution FIFOs live in a private directory, not a predictable
# path in the shared temp dir
class TestProcSubFifo < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @context = @repl.instance_variable_get(:@context)
  end

  def teardown
    @repl.send(:cleanup_proc_sub_fifos)
    @context.send(:cleanup_proc_sub_fifos) if @context.respond_to?(:cleanup_proc_sub_fifos, true)
  end

  def test_fifo_is_created_inside_a_private_directory
    path = @context.__proc_sub('echo hi', :in)
    dir = File.dirname(path)
    # Read first so the writer child never blocks on an unopened FIFO
    content = File.read(path)
    assert_equal "hi\n", content
    assert_not_equal File.realpath(Dir.tmpdir), File.realpath(dir), 'FIFO must not sit directly in the shared tmpdir'
    assert_equal 0o700, File.stat(dir).mode & 0o777
    assert_equal 'fifo', File.ftype(path)
  end

  def test_process_substitution_still_works_end_to_end
    Dir.mktmpdir('rubish_proc_sub') do |d|
      out = File.join(d, 'out.txt')
      execute("cat <(echo from_procsub) > #{out}")
      assert_equal "from_procsub\n", File.read(out)
    end
  end

  def test_cleanup_removes_fifo_and_its_directory
    path = @context.__proc_sub('echo bye', :in)
    File.read(path)
    @context.cleanup_proc_sub_fifos
    assert_false File.exist?(path)
    assert_false File.directory?(File.dirname(path))
  end
end
