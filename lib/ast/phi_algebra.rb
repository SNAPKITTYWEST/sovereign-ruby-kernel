# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::ast::phi_algebra
# frozen_string_literal: true

require_relative 'node'

module Sovereign
  module AST
    PHI     = (1 + Math.sqrt(5)) / 2.0
    PHI_INV = 1.0 / PHI
    PHI_HAT = -PHI_INV

    module PhiAlgebra
      def self.literal(value)
        Node.new(:lit, children: [value])
      end

      def self.phi(exponent = 1)
        Node.new(:phi, children: [exponent], meta: { value: PHI**exponent })
      end

      def self.phi_hat(exponent = 1)
        Node.new(:phi_hat, children: [exponent], meta: { value: PHI_HAT**exponent })
      end

      def self.add(left, right)
        Node.new(:add, children: [left, right])
      end

      def self.mul(left, right)
        Node.new(:mul, children: [left, right])
      end

      def self.norm(expr)
        Node.new(:norm, children: [expr, galois_conjugate(expr)])
      end

      def self.galois_conjugate(node)
        node.transform do |n|
          case n.type
          when :phi     then Node.new(:phi_hat, children: n.children)
          when :phi_hat then Node.new(:phi, children: n.children)
          else n
          end
        end
      end

      def self.trs_tree(depths, biases)
        terms = biases.map do |sym, weights|
          summands = depths.zip(weights).map do |d, b|
            mul(literal(b), phi(d + 1))
          end
          summands.reduce { |acc, s| add(acc, s) }
        end
        node = terms.reduce { |acc, t| add(acc, t) }
        Node.new(:trs, children: [node], meta: { symbol_count: biases.size })
      end

      def self.evaluate(node)
        case node.type
        when :lit     then node.children[0]
        when :phi     then PHI**node.children[0]
        when :phi_hat then PHI_HAT**node.children[0]
        when :add     then evaluate(node.children[0]) + evaluate(node.children[1])
        when :mul     then evaluate(node.children[0]) * evaluate(node.children[1])
        when :norm
          a = evaluate(node.children[0])
          b = evaluate(node.children[1])
          a * b
        when :trs     then evaluate(node.children[0])
        else raise "Unknown node type: #{node.type}"
        end
      end
    end
  end
end
