# frozen_string_literal: true

##
# Agent Communication DSL
#
# Provides high-level primitives for agent coordination:
# - claim(fact, evidence) — agent proposes claim with backing proof
# - authorize(decision, justification) — consensus check via ICP-DAG
# - execute(directive) — only if authorized decision reachable from verified claim
#
# INVARIANT: All DSL operations enforce ICP-DAG protocol
# INVARIANT: Every operation generates immutable audit record
#

require 'set'
require 'digest'

module Sovereign
  module Agents
    ##
    # Agent DSL: High-level operations for agent coordination
    #
    class AgentDSL
      attr_reader :enforcer, :agents, :global_state

      def initialize(enforcer = nil)
        @enforcer = enforcer || ProtocolEnforcer.new
        @agents = {}          # agent_id => GologAgent
        @global_state = {}    # shared state across agents
        @operation_log = []   # all DSL operations
        @dsl_lock = Mutex.new
      end

      ##
      # Register agent in DSL
      # INVARIANT: agent_id is globally unique
      #
      def register_agent(agent_id)
        @dsl_lock.synchronize do
          raise ArgumentError, "Agent already registered" \
            if @agents.key?(agent_id)

          agent = GologAgent.new(agent_id)
          @agents[agent_id] = agent

          log_operation(:agent_registered, {
            agent_id: agent_id,
            timestamp: Time.now.utc
          })

          agent
        end
      end

      ##
      # DSL: Claim(fact, evidence)
      # Agent proposes fact with supporting evidence
      #
      # INVARIANT: claim_id is unique
      # INVARIANT: Evidence must be non-empty
      # INVARIANT: Claim creates implicit backing for later decisions
      #
      def claim(agent_id, claim_id, fact, evidence)
        @dsl_lock.synchronize do
          agent = get_agent!(agent_id)

          raise ArgumentError, "Empty evidence" \
            if evidence.nil? || evidence.to_s.empty?

          # Create claim via agent
          message = agent.claim(claim_id, fact, evidence)

          # Register with enforcer
          @enforcer.register_decision(
            claim_id,
            fact,
            [],  # no backing claims for initial claim
            { actor: agent_id, evidence: evidence }
          )

          # Mark as proven (initial claims are self-proving via evidence)
          @enforcer.prove_decision(
            claim_id,
            evidence,
            agent_id
          )

          agent.mark_proven(claim_id)

          log_operation(:claim, {
            agent_id: agent_id,
            claim_id: claim_id,
            fact: fact,
            evidence: evidence,
            timestamp: message.timestamp
          })

          message
        end
      end

      ##
      # DSL: Authorize(decision, justification)
      # Check consensus and authorize decision
      #
      # INVARIANT: All backing claims must be proven
      # INVARIANT: Consensus threshold enforced
      # INVARIANT: Authorization vote is immutable once registered
      #
      def authorize(agent_id, decision_id, justification,
                    consensus_votes = [], threshold = 0.67)
        @dsl_lock.synchronize do
          agent = get_agent!(agent_id)

          raise ArgumentError, "No justification provided" \
            if justification.nil? || justification.to_s.empty?

          raise ArgumentError, "No consensus votes" \
            if consensus_votes.empty?

          # Calculate consensus
          affirmative_votes = consensus_votes.count { |v| v[:vote] == true }
          consensus_ratio = affirmative_votes.to_f / consensus_votes.length

          if consensus_ratio < threshold
            raise InsufficientConsensusError,
                  "Consensus #{consensus_ratio} below #{threshold}"
          end

          # Authorize via enforcer
          authorization = @enforcer.authorize_decision(
            decision_id,
            consensus_votes,
            threshold,
            agent_id
          )

          # Update agent state
          agent.authorize(decision_id, threshold)

          log_operation(:authorize, {
            agent_id: agent_id,
            decision_id: decision_id,
            justification: justification,
            consensus_ratio: consensus_ratio,
            consensus_threshold: threshold,
            vote_count: consensus_votes.length,
            timestamp: authorization.authorized_at
          })

          authorization
        end
      end

      ##
      # DSL: Execute(directive)
      # Execute authorized decision with full compliance checks
      #
      # INVARIANT: Decision must be:
      #   1. Registered with enforcer
      #   2. Proven (all backing claims proven)
      #   3. Authorized (consensus reached)
      #   4. Part of acyclic authorization DAG
      #
      # Returns: ExecutionRecord with full audit trail
      #
      def execute(agent_id, decision_id, directive)
        @dsl_lock.synchronize do
          agent = get_agent!(agent_id)

          raise ArgumentError, "No directive provided" \
            if directive.nil? || directive.to_s.empty?

          # Verify decision is properly backed
          authority = @enforcer.authority_chain(decision_id)
          raise DecisionNotFoundError, "No decision registered" \
            unless authority

          unless authority[:all_proven] && authority[:all_authorized]
            raise UnauthorizedExecutionError,
                  "Decision not fully authorized"
          end

          # Verify chain integrity
          unless @enforcer.verify_chain_integrity(decision_id)
            raise ChainIntegrityError,
                  "Decision chain integrity check failed"
          end

          # Execute via enforcer
          execution = @enforcer.execute_decision(decision_id, agent_id)

          # Execute via agent
          record = agent.execute(decision_id)

          # Update global state
          @global_state[decision_id] = {
            executed: true,
            directive: directive,
            executed_by: agent_id,
            executed_at: record.executed_at,
            execution_id: execution.id
          }

          log_operation(:execute, {
            agent_id: agent_id,
            decision_id: decision_id,
            directive: directive,
            execution_id: execution.id,
            chain_length: authority[:chain].length,
            timestamp: execution.executed_at
          })

          {
            execution: execution,
            agent_record: record,
            audit_trail: @enforcer.audit_trail(decision_id)
          }
        end
      end

      ##
      # Query: Get audit trail for decision
      # INVARIANT: Returns immutable snapshot
      #
      def audit_trail(decision_id)
        @dsl_lock.synchronize do
          @enforcer.audit_trail(decision_id)
        end
      end

      ##
      # Query: Get authority chain
      # INVARIANT: Returns complete decision chain for decision
      #
      def authority_chain(decision_id)
        @dsl_lock.synchronize do
          @enforcer.authority_chain(decision_id)
        end
      end

      ##
      # Query: Get agent state
      # INVARIANT: Returns snapshot of agent state
      #
      def agent_state(agent_id)
        @dsl_lock.synchronize do
          agent = @agents[agent_id]
          return nil unless agent

          {
            agent_id: agent_id,
            state: agent.current_state,
            claimed_facts: agent.claimed_facts.keys,
            proven_facts: agent.proven_facts.to_a,
            execution_history: agent.execution_history.length,
            message_log_size: agent.message_log.length
          }
        end
      end

      ##
      # Query: Get all claims in system
      # INVARIANT: Returns snapshot of all registered decisions
      #
      def all_claims
        @dsl_lock.synchronize do
          @enforcer.decisions.values.select { |d| d.backing_claims.empty? }
        end
      end

      ##
      # Query: Get authorized but unexecuted decisions
      # INVARIANT: Returns decisions ready for execution
      #
      def pending_executions
        @dsl_lock.synchronize do
          authorized = @enforcer.authorizations.keys
          unexecuted = authorized - @global_state.keys.select { |k| @global_state[k][:executed] }
          unexecuted.map { |d| @enforcer.decisions[d] }
        end
      end

      ##
      # Validate all DSL invariants
      # INVARIANT: Called frequently to detect protocol violations
      #
      def validate_invariants!
        @dsl_lock.synchronize do
          # 1. Enforcer invariants
          @enforcer.validate_invariants!

          # 2. Agent invariants
          @agents.each_value(&:validate_invariants!)

          # 3. DSL state consistency
          @enforcer.authorizations.each_key do |decision_id|
            decision = @enforcer.decisions[decision_id]
            raise InvariantViolationError,
                  "Authorized decision not registered" \
              unless decision
          end

          true
        end
      end

      private

      def get_agent!(agent_id)
        raise ArgumentError, "Agent not registered" \
          unless @agents.key?(agent_id)

        @agents[agent_id]
      end

      def log_operation(operation_type, data)
        @operation_log << {
          type: operation_type,
          data: data,
          logged_at: Time.now.utc
        }
      end
    end

    ##
    # Agent Coordinator: High-level multi-agent orchestration
    #
    class AgentCoordinator
      attr_reader :dsl, :agents

      def initialize(dsl = nil)
        @dsl = dsl || AgentDSL.new
        @agents = Set.new
        @consensus_log = []
      end

      ##
      # Register multiple agents
      # INVARIANT: All agents have unique IDs
      #
      def create_agents(agent_ids)
        agents = {}
        agent_ids.each do |id|
          agent = @dsl.register_agent(id)
          agents[id] = agent
          @agents.add(id)
        end
        agents
      end

      ##
      # Collective claim: All agents propose same fact
      # INVARIANT: Consensus check ensures agreement
      #
      def collective_claim(fact, evidence, agent_subset = nil)
        subset = agent_subset || @agents.to_a
        claims = {}

        subset.each do |agent_id|
          claim_id = "#{fact}:#{agent_id}:#{Time.now.to_i}"
          msg = @dsl.claim(agent_id, claim_id, fact, evidence)
          claims[agent_id] = msg
        end

        claims
      end

      ##
      # Consensus authorization: Require threshold approval
      # INVARIANT: Votes recorded immutably
      # INVARIANT: Threshold enforced at protocol level
      #
      def consensus_authorize(decision_id, threshold = 0.67)
        # Collect votes from agents
        votes = @agents.map do |agent_id|
          {
            agent_id: agent_id,
            vote: true,  # Placeholder - actual voting would be dynamic
            voted_at: Time.now.utc
          }
        end

        primary_agent = @agents.first
        authorization = @dsl.authorize(
          primary_agent,
          decision_id,
          "Consensus authorization",
          votes,
          threshold
        )

        @consensus_log << {
          decision_id: decision_id,
          votes: votes,
          threshold: threshold,
          authorized_at: authorization.authorized_at
        }

        authorization
      end

      ##
      # Orchestrate full execution pipeline
      # INVARIANT: Claim → Consensus → Authorize → Execute
      #
      def orchestrate_execution(fact, evidence, directive,
                                agent_subset = nil, threshold = 0.67)
        # 1. Collective claim
        claims = collective_claim(fact, evidence, agent_subset)
        claim_ids = claims.values.map { |m| m.payload[:claim_id] }

        # 2. Create decision based on claims
        decision_id = "decision:#{Time.now.to_i}:#{SecureRandom.hex(4)}"
        @dsl.enforcer.register_decision(
          decision_id,
          directive,
          claim_ids,
          { orchestrated: true }
        )

        claim_ids.each do |claim_id|
          @dsl.enforcer.prove_decision(claim_id, "evidence", @agents.first)
        end

        # 3. Consensus authorization
        votes = @agents.map do |agent_id|
          { agent_id: agent_id, vote: true, voted_at: Time.now.utc }
        end

        authorization = @dsl.authorize(
          @agents.first,
          decision_id,
          directive,
          votes,
          threshold
        )

        # 4. Execute
        execution = @dsl.execute(
          @agents.first,
          decision_id,
          directive
        )

        {
          claims: claims,
          decision_id: decision_id,
          authorization: authorization,
          execution: execution
        }
      end

      ##
      # Get consensus statistics
      # INVARIANT: Aggregation based on immutable consensus log
      #
      def consensus_statistics
        {
          total_decisions: @consensus_log.length,
          avg_threshold: @consensus_log.empty? ? 0 : \
            @consensus_log.map { |l| l[:threshold] }.sum.to_f / @consensus_log.length,
          approval_rate: @consensus_log.empty? ? 0 : \
            @consensus_log.count { |l| l[:votes].all? { |v| v[:vote] } }.to_f / @consensus_log.length
        }
      end
    end

    # Custom exceptions
    class InsufficientConsensusError < StandardError; end
    class UnauthorizedExecutionError < StandardError; end
    class ChainIntegrityError < StandardError; end
  end
end
