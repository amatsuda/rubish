# frozen_string_literal: true

require_relative 'test_helper'

# Job control needs fiddle for tcsetpgrp/tcgetpgrp. When the gem is not
# installed the shell must keep working without terminal hand-off instead
# of dying on the first external command
class TestTerminalWithoutFiddle < Test::Unit::TestCase
  def setup
    @saved_libc = Rubish::Terminal.instance_variable_get(:@libc)
    Rubish::Terminal.instance_variable_set(:@libc, nil)
    Rubish.singleton_class.alias_method(:__orig_require_library, :require_library)
    Rubish.define_singleton_method(:require_library) { |name| raise LoadError, "cannot load such file -- #{name}" }
  end

  def teardown
    Rubish.singleton_class.remove_method(:require_library)
    Rubish.singleton_class.alias_method(:require_library, :__orig_require_library)
    Rubish.singleton_class.remove_method(:__orig_require_library)
    Rubish::Terminal.instance_variable_set(:@libc, @saved_libc)
  end

  def test_set_foreground_is_a_no_op_without_fiddle
    assert_nothing_raised { Rubish::Terminal.set_foreground(Process.pid) }
  end

  def test_get_foreground_is_nil_without_fiddle
    assert_nil Rubish::Terminal.get_foreground
  end
end
