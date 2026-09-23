# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::swarm::agent
# frozen_string_literal: true

require_relative '../kernel/worm'

module Sovereign
  module Swarm
    class Agent
      attr_reader :id, :role, :state, :inbox, :outbox

      ROLES = %i[
        parser       rewriter    evaluator
        verifier     sealer      synthesizer
        scout        governor
      ].freeze

      def initialize(id:, role:)
        raise ArgumentError, "Unknown role: #{role}" unless ROLES.include?(role)
        @id = id
        @role = role
        @state = :idle
        @inbox = Queue.new
        @outbox = Queue.new
        @generation = 0
      end

      def receive(message)
        @inbox << message
      end

      def process
        return if @inbox.empty?
        @state = :working
        msg = @inbox.pop(true) rescue nil
        return unless msg

        result = dispatch(msg)
        @generation += 1
        @outbox << { from: @id, role: @role, gen: @generation, result: result }
        @state = :idle
        result
      end

      private

      def dispatch(msg)
        case @role
        when :parser      then parse_task(msg)
        when :rewriter    then rewrite_task(msg)
        when :evaluator   then evaluate_task(msg)
        when :verifier    then verify_task(msg)
        when :sealer      then seal_task(msg)
        when :synthesizer then synthesize_task(msg)
        when :scout       then scout_task(msg)
        when :governor    then govern_task(msg)
        end
      end

      def parse_task(msg)
        tree = msg[:tree]
        { action: :parsed, depth: tree.depth, arity: tree.arity, sexp: tree.to_sexp[0..100] }
      end

      def rewrite_task(msg)
        tree = msg[:tree]
        AST::Rewrite.normalize(tree)
      end

      def evaluate_task(msg)
        tree = msg[:tree]
        { value: AST::PhiAlgebra.evaluate(tree) }
      end

      def verify_task(msg)
        tree = msg[:tree]
        { confluent: AST::Rewrite.confluent?(tree) }
      end

      def seal_task(msg)
        Kernel::WORM.seal("swarm:#{@id}", msg[:evidence] || {})
      end

      def synthesize_task(msg)
        source_tree = msg[:tree]
        target = msg[:target] || :self
        emit_self_object(source_tree, target)
      end

      def scout_task(msg)
        tree = msg[:tree]
        tree.fold([]) do |acc, node|
          acc << { type: node.type, depth: node.depth } if node.depth > 3
          acc
        end
      end

      def govern_task(msg)
        msg[:gate]&.state
      end

      def emit_self_object(tree, target)
        slots = []
        tree.fold(slots) do |acc, node|
          acc << { name: node.type, arity: node.arity, leaf: node.leaf? }
          acc
        end
        { target: target, slots: slots, prototype_chain: build_prototype_chain(tree) }
      end

      def build_prototype_chain(tree)
        chain = []
        current = tree
        while current.is_a?(AST::Node) && !current.leaf?
          chain << current.type
          current = current.children.find { |c| c.is_a?(AST::Node) }
        end
        chain
      end
    end
  end
end
