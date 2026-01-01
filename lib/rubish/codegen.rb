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
      when AST::And
        generate_and(node)
      when AST::Or
        generate_or(node)
      else
        raise "Unknown AST node: #{node.class}"
      end
    end

    private

    def generate_command(node)
      args = node.args.map { |a| generate_arg(a) }.join(', ')
      cmd = if args.empty?
              "__cmd(#{escape_string(node.name)})"
            else
              "__cmd(#{escape_string(node.name)}, #{args})"
            end

      # Append block if present
      if node.block
        cmd = "#{cmd} #{node.block}"
      end

      cmd
    end

    def generate_arg(arg)
      case arg
      when String
        escape_string(arg)
      when AST::ArrayLiteral
        arg.value  # Already valid Ruby: [1, 2, 3]
      when AST::RegexpLiteral
        arg.value  # Already valid Ruby: /pattern/
      else
        arg.inspect
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
      "#{generate(node.command)}.#{op_method}(#{escape_string(node.target)})"
    end

    def generate_background(node)
      "__background { #{generate(node.command)} }"
    end

    def generate_and(node)
      "__and_cmd(-> { #{generate(node.left)} }, -> { #{generate(node.right)} })"
    end

    def generate_or(node)
      "__or_cmd(-> { #{generate(node.left)} }, -> { #{generate(node.right)} })"
    end

    def escape_string(str)
      str.inspect
    end
  end
end
