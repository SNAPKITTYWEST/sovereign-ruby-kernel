# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::ast::rewrite
# frozen_string_literal: true

require_relative 'node'

module Sovereign
  module AST
    module Rewrite
      Rule = Struct.new(:name, :pattern, :replacement, keyword_init: true)

      RULES = [
        Rule.new(
          name: :phi_squared,
          pattern: ->(n) { n.type == :phi && n.children[0] == 2 },
          replacement: ->(n) {
            PhiAlgebra.add(PhiAlgebra.phi(1), PhiAlgebra.literal(1))
          }
        ),
        Rule.new(
          name: :mul_identity,
          pattern: ->(n) { n.type == :mul && n.children[0].type == :lit && n.children[0].children[0] == 1.0 },
          replacement: ->(n) { n.children[1] }
        ),
        Rule.new(
          name: :add_zero,
          pattern: ->(n) { n.type == :add && n.children[1].type == :lit && n.children[1].children[0] == 0 },
          replacement: ->(n) { n.children[0] }
        ),
        Rule.new(
          name: :norm_product,
          pattern: ->(n) { n.type == :norm },
          replacement: ->(n) {
            PhiAlgebra.mul(n.children[0], n.children[1])
          }
        )
      ].freeze

      def self.apply_once(node, rules = RULES)
        rules.each do |rule|
          if rule.pattern.call(node)
            return { node: rule.replacement.call(node), applied: rule.name }
          end
        end
        { node: node, applied: nil }
      end

      def self.normalize(node, rules = RULES, max_steps: 100)
        trace = []
        current = node
        max_steps.times do |step|
          changed = false
          current = current.transform do |n|
            result = apply_once(n, rules)
            if result[:applied]
              trace << { step: step, rule: result[:applied], sexp: result[:node].to_sexp }
              changed = true
              result[:node]
            else
              n
            end
          end
          break unless changed
        end
        { normal_form: current, trace: trace }
      end

      def self.confluent?(node, rules = RULES)
        r1 = normalize(node, rules)
        reversed = normalize(node, rules.reverse)
        r1[:normal_form] == reversed[:normal_form]
      end
    end
  end
end
