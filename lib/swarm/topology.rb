# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::swarm::topology
# frozen_string_literal: true

require_relative 'agent'

module Sovereign
  module Swarm
    class Topology
      attr_reader :agents, :edges

      def initialize
        @agents = {}
        @edges = []
      end

      def add_agent(id:, role:)
        agent = Agent.new(id: id, role: role)
        @agents[id] = agent
        agent
      end

      def connect(from_id, to_id, channel: :default)
        @edges << { from: from_id, to: to_id, channel: channel }
      end

      def route(from_id)
        @edges.select { |e| e[:from] == from_id }.map { |e| @agents[e[:to]] }
      end

      def tick
        results = []
        @agents.each_value do |agent|
          result = agent.process
          next unless result

          route(agent.id).each do |downstream|
            downstream.receive({ from: agent.id, tree: result[:normal_form] || result })
          end
          results << { agent: agent.id, role: agent.role, result: result }
        end
        results
      end

      def self.sovereign_pipeline
        topo = new

        topo.add_agent(id: :scout_0,    role: :scout)
        topo.add_agent(id: :parse_0,    role: :parser)
        topo.add_agent(id: :parse_1,    role: :parser)
        topo.add_agent(id: :rewrite_0,  role: :rewriter)
        topo.add_agent(id: :rewrite_1,  role: :rewriter)
        topo.add_agent(id: :eval_0,     role: :evaluator)
        topo.add_agent(id: :verify_0,   role: :verifier)
        topo.add_agent(id: :synth_0,    role: :synthesizer)
        topo.add_agent(id: :synth_1,    role: :synthesizer)
        topo.add_agent(id: :seal_0,     role: :sealer)
        topo.add_agent(id: :governor_0, role: :governor)

        # Scout fans out to parsers
        topo.connect(:scout_0, :parse_0, channel: :even)
        topo.connect(:scout_0, :parse_1, channel: :odd)

        # Parsers → rewriters (parallel)
        topo.connect(:parse_0, :rewrite_0)
        topo.connect(:parse_1, :rewrite_1)

        # Rewriters converge → evaluator → verifier
        topo.connect(:rewrite_0, :eval_0)
        topo.connect(:rewrite_1, :eval_0)
        topo.connect(:eval_0, :verify_0)

        # Verifier fans → synthesizers (Ruby→Self translation)
        topo.connect(:verify_0, :synth_0, channel: :slots)
        topo.connect(:verify_0, :synth_1, channel: :protos)

        # Synthesizers → sealer
        topo.connect(:synth_0, :seal_0)
        topo.connect(:synth_1, :seal_0)

        # Governor observes everything
        topo.connect(:seal_0, :governor_0)

        topo
      end

      def to_dot
        lines = ["digraph SwarmTopology {", "  rankdir=LR;"]
        @agents.each do |id, a|
          lines << "  #{id} [label=\"#{id}\\n(#{a.role})\"];"
        end
        @edges.each do |e|
          label = e[:channel] == :default ? '' : " [label=\"#{e[:channel]}\"]"
          lines << "  #{e[:from]} -> #{e[:to]}#{label};"
        end
        lines << "}"
        lines.join("\n")
      end
    end
  end
end
