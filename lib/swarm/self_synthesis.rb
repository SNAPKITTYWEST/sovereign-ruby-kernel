# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::swarm::self_synthesis
# frozen_string_literal: true

require_relative '../ast/node'
require_relative '../ast/phi_algebra'

module Sovereign
  module Swarm
    # Translates AST trees into Self-language prototype objects.
    # Self uses slot-based prototypal inheritance — every AST node
    # becomes a Self object with data slots (value, type) and
    # parent slots (prototype chain following the tree structure).
    module SelfSynthesis
      def self.emit(tree, indent: 0)
        pad = '  ' * indent
        case tree
        when AST::Node
          if tree.leaf?
            emit_leaf(tree, pad)
          else
            emit_interior(tree, pad, indent)
          end
        else
          "#{pad}(| value = #{tree.inspect} |)"
        end
      end

      def self.emit_module(kernel)
        forest = kernel.to_ast_forest
        lines = []
        lines << '(| "Sovereign Symbolic Kernel — Self prototype hierarchy"'
        lines << ''
        lines << '  trs = ' + emit(forest[:trs], indent: 1) + '.'
        lines << ''
        lines << '  conjugate = ' + emit(forest[:conjugate], indent: 1) + '.'
        lines << ''
        lines << '  norm = ' + emit(forest[:norm], indent: 1) + '.'
        lines << ''

        forest[:symbols].each do |sym, subtree|
          lines << "  #{sym.to_s.downcase} = " + emit(subtree, indent: 1) + '.'
          lines << ''
        end

        lines << '  evaluate = ('
        lines << '    trs value + conjugate value'
        lines << '  ).'
        lines << ''
        lines << '  verify = ('
        lines << '    | delta |'
        lines << "    delta: (evaluate - #{Kernel::SymbolicKernel::CANONICAL_TRS}) abs."
        lines << '    delta < 0.001'
        lines << '  ).'
        lines << '|)'
        lines.join("\n")
      end

      private_class_method

      def self.emit_leaf(node, pad)
        val = node.children[0]
        "(| type <- ##{node.type}. value <- #{val.inspect} |)"
      end

      def self.emit_interior(node, pad, indent)
        child_pad = '  ' * (indent + 1)
        slots = node.children.each_with_index.map do |c, i|
          "#{child_pad}child#{i} = #{emit(c, indent: indent + 1)}"
        end.join(".\n")

        lines = []
        lines << "(| type <- ##{node.type}."
        lines << "#{child_pad}arity <- #{node.arity}."
        lines << slots + '.'
        lines << "#{child_pad}parent* = traits clonable"
        lines << "#{pad}|)"
        lines.join("\n")
      end
    end
  end
end
