# frozen_string_literal: true

module Rubish
  class Codegen
    def generate(node)
      case node
      when AST::Command
        generate_command(node)
      when AST::Pipeline
        generate_pipeline(node)
      when AST::List
        generate_list(node)
      when AST::Redirect
        generate_redirect(node)
      when AST::Background
        generate_background(node)
      else
        raise "Unknown AST node: #{node.class}"
      end
    end

    private

    def generate_command(node)
      args = node.args.map { |a| escape_arg(a) }.join(', ')
      if args.empty?
        "__cmd(#{escape_arg(node.name)})"
      else
        "__cmd(#{escape_arg(node.name)}, #{args})"
      end
    end

    def generate_pipeline(node)
      node.commands.map { |c| generate(c) }.join(' | ')
    end

    def generate_list(node)
      node.commands.map { |c| generate(c) }.join('; ')
    end

    def generate_redirect(node)
      op_method = case node.operator
                  when '>' then 'redirect_out'
                  when '>>' then 'redirect_append'
                  when '<' then 'redirect_in'
                  when '2>' then 'redirect_err'
                  end
      "#{generate(node.command)}.#{op_method}(#{escape_arg(node.target)})"
    end

    def generate_background(node)
      "__background { #{generate(node.command)} }"
    end

    def escape_arg(str)
      str.inspect
    end
  end
end
