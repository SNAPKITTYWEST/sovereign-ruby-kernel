# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::kernel::symbolic_kernel
# frozen_string_literal: true

require_relative 'worm'
require_relative 'governance'
require_relative '../ast/node'
require_relative '../ast/phi_algebra'
require_relative '../ast/rewrite'

module Sovereign
  module Kernel
    class SymbolicKernel
      attr_reader :tree, :gate, :evaluation_cache

      DEPTHS = [0, 1, 2, 3, 4, 5, 5, 6].freeze
      BIASES = {
        ME:     [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
        AN:     [0.8, 1.4, 0.8, 0.8, 0.8, 1.2, 0.8, 0.8],
        KI:     [0.9, 0.9, 1.4, 0.9, 1.4, 0.9, 0.9, 0.9],
        DINGIR: [0.7, 0.7, 0.7, 0.7, 0.7, 1.6, 1.8, 1.6]
      }.freeze

      CANONICAL_TRS = 388.985128

      def initialize
        @gate = Governance.new_gate
        @tree = AST::PhiAlgebra.trs_tree(DEPTHS, BIASES)
        @evaluation_cache = {}
        WORM.seal('kernel:init', { tree_depth: @tree.depth, tree_sexp: @tree.to_sexp[0..200] })
      end

      def evaluate
        @evaluation_cache[:trs] ||= AST::PhiAlgebra.evaluate(@tree)
      end

      def conjugate_tree
        @conjugate_tree ||= AST::PhiAlgebra.galois_conjugate(@tree)
      end

      def evaluate_conjugate
        @evaluation_cache[:conjugate] ||= AST::PhiAlgebra.evaluate(conjugate_tree)
      end

      def norm
        @evaluation_cache[:norm] ||= evaluate * evaluate_conjugate
      end

      def normalize
        @normalization ||= AST::Rewrite.normalize(@tree)
      end

      def verify!
        trs = evaluate
        delta = (trs - CANONICAL_TRS).abs
        conj = evaluate_conjugate
        n = norm

        evidence = {
          trs: trs.round(6),
          conjugate: conj.round(6),
          norm: n.round(6),
          delta: delta.round(6),
          canonical: CANONICAL_TRS,
          confluent: AST::Rewrite.confluent?(@tree),
          tree_depth: @tree.depth
        }

        if delta < 0.001
          @gate.transition!(:verified, evidence: evidence)
          WORM.seal('kernel:verified', evidence)
          evidence
        else
          @gate.transition!(:rejected, evidence: evidence)
          raise "TRS divergence: Δ=#{delta}"
        end
      end

      def seal!
        @gate.require_sealed! rescue nil
        verify! if @gate.state == :init
        @gate.transition!(:sealed, evidence: { seal: WORM.last_seal }) if @gate.state == :verified
        WORM.last_seal
      end

      def to_ast_forest
        {
          trs:       @tree,
          conjugate: conjugate_tree,
          norm:      AST::PhiAlgebra.norm(@tree),
          symbols:   BIASES.keys.map { |s| [s, symbol_subtree(s)] }.to_h
        }
      end

      private

      def symbol_subtree(sym)
        weights = BIASES[sym]
        summands = DEPTHS.zip(weights).map do |d, b|
          AST::PhiAlgebra.mul(AST::PhiAlgebra.literal(b), AST::PhiAlgebra.phi(d + 1))
        end
        summands.reduce { |acc, s| AST::PhiAlgebra.add(acc, s) }
      end
    end
  end
end
