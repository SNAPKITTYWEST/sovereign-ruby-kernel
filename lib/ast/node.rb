# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::ast::node
# frozen_string_literal: true

module Sovereign
  module AST
    class Node
      attr_reader :type, :children, :meta

      def initialize(type, children: [], meta: {})
        @type = type.to_sym
        @children = children.freeze
        @meta = meta.freeze
      end

      def leaf? = children.empty?
      def arity = children.length

      def transform(&block)
        new_children = children.map do |c|
          c.is_a?(Node) ? c.transform(&block) : c
        end
        block.call(self.class.new(type, children: new_children, meta: meta))
      end

      def fold(acc, &block)
        result = block.call(acc, self)
        children.each do |c|
          result = c.fold(result, &block) if c.is_a?(Node)
        end
        result
      end

      def depth
        return 0 if leaf?
        1 + children.filter_map { |c| c.is_a?(Node) ? c.depth : nil }.max.to_i
      end

      def to_sexp
        return "(#{type})" if leaf?
        inner = children.map { |c| c.is_a?(Node) ? c.to_sexp : c.inspect }.join(' ')
        "(#{type} #{inner})"
      end

      def ==(other)
        other.is_a?(Node) && type == other.type && children == other.children
      end

      def hash = [type, children].hash
      alias eql? ==
    end
  end
end
