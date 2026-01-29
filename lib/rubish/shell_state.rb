# frozen_string_literal: true

module Rubish
  # ShellState holds per-session shell state as instance variables.
  # This enables proper isolation between shell sessions and simplifies testing.
  class ShellState
    # Variables state
    attr_accessor :shell_vars, :arrays, :assoc_arrays, :namerefs, :var_attributes, :readonly_vars, :local_scope_stack

    def initialize
      # Variables state
      @shell_vars = {}
      @arrays = {}
      @assoc_arrays = {}
      @namerefs = {}
      @var_attributes = {}
      @readonly_vars = {}
      @local_scope_stack = []
    end

    def clear_variables
      @shell_vars.clear
      @arrays.clear
      @assoc_arrays.clear
      @namerefs.clear
      @var_attributes.clear
      @readonly_vars.clear
      @local_scope_stack.clear
    end
  end
end
