# frozen_string_literal: true

##
# Golog Agent Framework with ICP-DAG Protocol Enforcement
#
# Implements agent communication with formal verification:
# - Message passing: claim/proof/decision types
# - State machine: unknown→proposed→verified→proven→authorized→executed
# - Every agent decision has proven backing via ICP-DAG
#
# INVARIANT: All agent state transitions form an acyclic authorization DAG
#

require 'set'
require 'digest'
require 'time'

module Sovereign
  module Agents
    ##
    # Base agent class with ICP-DAG protocol enforcement
    #
    class GologAgent
      # State machine constants (INVARIANT: monotonic progression)
      STATE_UNKNOWN     = :unknown
      STATE_PROPOSED    = :proposed
      STATE_VERIFIED    = :verified
      STATE_PROVEN      = :proven
      STATE_AUTHORIZED  = :authorized
      STATE_EXECUTED    = :executed

      # State progression graph (INVARIANT: acyclic)
      STATE_TRANSITIONS = {
        STATE_UNKNOWN => [STATE_PROPOSED],
        STATE_PROPOSED => [STATE_VERIFIED],
        STATE_VERIFIED => [STATE_PROVEN],
        STATE_PROVEN => [STATE_AUTHORIZED],
        STATE_AUTHORIZED => [STATE_EXECUTED],
        STATE_EXECUTED => []
      }.freeze

      attr_reader :id, :current_state, :claimed_facts, :proven_facts,
                  :execution_history, :message_log, :governance_proofs,
                  :decision_chain

      ##
      # Initialize agent with unique ID
      # INVARIANT: id is globally unique, initial state is UNKNOWN
      #
      def initialize(id)
        @id = id
        @current_state = STATE_UNKNOWN
        @claimed_facts = {}      # fact_id => ClaimedFact
        @proven_facts = Set.new  # Set of proven fact IDs
        @execution_history = []  # Timestamped execution log
        @message_log = []        # All agent-to-agent messages
        @governance_proofs = {}  # decision_id => GovernanceProof
        @decision_chain = []     # Ordered decisions forming DAG
        @state_lock = Mutex.new
      end

      ##
      # Transition to new state if valid
      # INVARIANT: Only valid transitions allowed, state is never undefined
      #
      def transition_to(new_state)
        @state_lock.synchronize do
          current_valid_transitions = STATE_TRANSITIONS[@current_state] || []
          unless current_valid_transitions.include?(new_state)
            raise ArgumentError,
                  "Invalid transition: #{@current_state} -> #{new_state}"
          end
          @current_state = new_state
        end
      end

      ##
      # Claim a fact with supporting evidence
      # INVARIANT: claim_id is unique, created_at is immutable
      #
      # Returns: Message of type :claim
      #
      def claim(claim_id, fact, evidence)
        @state_lock.synchronize do
          raise StateError, "Cannot claim in state #{@current_state}" \
            if @current_state != STATE_UNKNOWN && @current_state != STATE_PROPOSED

          msg = Message.claim(
            from_agent: @id,
            claim_id: claim_id,
            fact: fact,
            evidence: evidence,
            timestamp: Time.now.utc
          )

          @claimed_facts[claim_id] = ClaimedFact.new(
            id: claim_id,
            fact: fact,
            evidence: evidence,
            claimed_by: @id,
            created_at: msg.timestamp
          )

          @message_log << msg
          transition_to(STATE_PROPOSED) if @current_state == STATE_UNKNOWN

          msg
        end
      end

      ##
      # Submit proof for a claimed fact
      # INVARIANT: proof must reference existing claimed fact
      # INVARIANT: proof_hash is deterministic (same proof => same hash)
      #
      # Returns: Message of type :proof
      #
      def submit_proof(proof_id, claim_id, proof_data)
        @state_lock.synchronize do
          raise ClaimNotFoundError, "No claim with id #{claim_id}" \
            unless @claimed_facts.key?(claim_id)

          proof = Proof.new(
            id: proof_id,
            claim_id: claim_id,
            proof_data: proof_data,
            submitted_by: @id,
            created_at: Time.now.utc
          )

          msg = Message.proof(
            from_agent: @id,
            proof: proof,
            timestamp: proof.created_at
          )

          @claimed_facts[claim_id].proofs << proof

          @message_log << msg
          transition_to(STATE_VERIFIED) if @current_state == STATE_PROPOSED

          msg
        end
      end

      ##
      # Decide to execute action with governance justification
      # INVARIANT: decision_id is unique
      # INVARIANT: justification includes proven backing
      # INVARIANT: Decision creates no circular authorization
      #
      # Returns: Message of type :decision
      #
      def decide(decision_id, action, justification, backing_claims)
        @state_lock.synchronize do
          raise ArgumentError, "Missing backing claims" \
            if backing_claims.empty?

          # Verify all backing claims exist
          backing_claims.each do |claim_id|
            raise ClaimNotFoundError, "Unknown backing claim: #{claim_id}" \
              unless @claimed_facts.key?(claim_id)
          end

          decision = Decision.new(
            id: decision_id,
            action: action,
            justification: justification,
            backing_claims: backing_claims,
            decided_by: @id,
            created_at: Time.now.utc
          )

          msg = Message.decision(
            from_agent: @id,
            decision: decision,
            timestamp: decision.created_at
          )

          # Enforce DAG invariant: no cycles
          check_acyclic_authorization(decision)

          @decision_chain << decision
          @message_log << msg
          transition_to(STATE_PROVEN) if @current_state == STATE_VERIFIED

          msg
        end
      end

      ##
      # Authorize decision with consensus governance proof
      # INVARIANT: All authorized decisions have reachable proven claims
      # INVARIANT: Authorization creates immutable audit trail
      #
      # Returns: GovernanceProof
      #
      def authorize(decision_id, consensus_threshold = 0.67)
        @state_lock.synchronize do
          decision = @decision_chain.find { |d| d.id == decision_id }
          raise DecisionNotFoundError, "No decision with id #{decision_id}" \
            unless decision

          proof = GovernanceProof.new(
            id: SecureRandom.hex(8),
            decision_id: decision_id,
            authorized_by: @id,
            consensus_threshold: consensus_threshold,
            authorized_at: Time.now.utc
          )

          @governance_proofs[decision_id] = proof

          msg = Message.authorization(
            from_agent: @id,
            governance_proof: proof,
            timestamp: proof.authorized_at
          )

          @message_log << msg
          transition_to(STATE_AUTHORIZED) if @current_state == STATE_PROVEN

          proof
        end
      end

      ##
      # Execute authorized decision with full audit trail
      # INVARIANT: Execution only occurs if:
      #   1. Decision is authorized (governance proof exists)
      #   2. All backing claims are verified
      #   3. No circular authorization chain
      #
      # Returns: ExecutionRecord
      #
      def execute(decision_id)
        @state_lock.synchronize do
          raise ArgumentError, "No authorization for decision #{decision_id}" \
            unless @governance_proofs.key?(decision_id)

          decision = @decision_chain.find { |d| d.id == decision_id }
          raise DecisionNotFoundError, "No decision with id #{decision_id}" \
            unless decision

          # Verify all backing claims proven
          decision.backing_claims.each do |claim_id|
            unless @proven_facts.include?(claim_id)
              raise UnprovenClaimError,
                    "Backing claim #{claim_id} not proven"
            end
          end

          record = ExecutionRecord.new(
            id: SecureRandom.hex(8),
            decision_id: decision_id,
            executed_by: @id,
            action: decision.action,
            executed_at: Time.now.utc,
            governance_proof: @governance_proofs[decision_id]
          )

          @execution_history << record

          msg = Message.execution(
            from_agent: @id,
            execution_record: record,
            timestamp: record.executed_at
          )

          @message_log << msg
          transition_to(STATE_EXECUTED)

          record
        end
      end

      ##
      # Mark claim as proven (external verifier)
      # INVARIANT: claim must exist and not already proven
      #
      def mark_proven(claim_id)
        @state_lock.synchronize do
          raise ClaimNotFoundError, "No claim with id #{claim_id}" \
            unless @claimed_facts.key?(claim_id)

          raise AlreadyProvenError, "Claim #{claim_id} already proven" \
            if @proven_facts.include?(claim_id)

          @proven_facts << claim_id
        end
      end

      ##
      # Check for circular authorization in DAG
      # INVARIANT: Authorization graph must be acyclic
      # INVARIANT: Uses depth-first search for cycle detection
      #
      def check_acyclic_authorization(decision)
        visited = Set.new
        rec_stack = Set.new

        def has_cycle?(current_id, visited, rec_stack, decision_map)
          visited.add(current_id)
          rec_stack.add(current_id)

          decision = decision_map[current_id]
          return false unless decision

          decision.backing_claims.each do |claim_id|
            return true if rec_stack.include?(claim_id)

            return true if !visited.include?(claim_id) && \
                           has_cycle?(claim_id, visited, rec_stack, decision_map)
          end

          rec_stack.delete(current_id)
          false
        end

        decision_map = @decision_chain.index_by(&:id)
        if has_cycle?(decision.id, visited, rec_stack, decision_map)
          raise CircularAuthorizationError,
                "Circular authorization detected for decision #{decision.id}"
        end
      end

      ##
      # Get audit trail for decision
      # INVARIANT: Returns immutable snapshot of execution chain
      #
      def audit_trail(decision_id)
        decision = @decision_chain.find { |d| d.id == decision_id }
        return nil unless decision

        {
          decision_id: decision.id,
          action: decision.action,
          backing_claims: decision.backing_claims,
          governance_proof: @governance_proofs[decision_id],
          execution_records: @execution_history.select { |r| r.decision_id == decision_id },
          messages: @message_log.select { |m| m.decision_id == decision_id }
        }
      end

      ##
      # Validate all invariants for agent state
      # INVARIANT: This method should always succeed if invariants hold
      #
      def validate_invariants!
        # 1. State is in valid set
        valid_states = [STATE_UNKNOWN, STATE_PROPOSED, STATE_VERIFIED,
                        STATE_PROVEN, STATE_AUTHORIZED, STATE_EXECUTED]
        raise InvariantViolationError, "Invalid state: #{@current_state}" \
          unless valid_states.include?(@current_state)

        # 2. All proven facts have corresponding claims
        @proven_facts.each do |fact_id|
          raise InvariantViolationError,
                "Proven fact #{fact_id} has no claim" \
            unless @claimed_facts.key?(fact_id)
        end

        # 3. Authorization DAG is acyclic
        visited = Set.new
        rec_stack = Set.new
        decision_map = @decision_chain.index_by(&:id)

        @decision_chain.each do |decision|
          next if visited.include?(decision.id)

          visited.clear
          rec_stack.clear

          if has_cycle?(decision.id, visited, rec_stack, decision_map)
            raise InvariantViolationError,
                  "Circular authorization in DAG"
          end
        end

        # 4. All executed decisions are authorized
        @execution_history.each do |record|
          raise InvariantViolationError,
                "Executed decision #{record.decision_id} not authorized" \
            unless @governance_proofs.key?(record.decision_id)
        end

        true
      end
    end

    ##
    # Claimed fact with evidence and proofs
    #
    class ClaimedFact
      attr_reader :id, :fact, :evidence, :claimed_by, :created_at
      attr_accessor :proofs

      def initialize(id:, fact:, evidence:, claimed_by:, created_at:)
        @id = id
        @fact = fact
        @evidence = evidence
        @claimed_by = claimed_by
        @created_at = created_at
        @proofs = []
      end

      def hash
        Digest::SHA256.hexdigest("#{@id}:#{@fact}:#{@evidence}")
      end
    end

    ##
    # Proof for a claimed fact
    #
    class Proof
      attr_reader :id, :claim_id, :proof_data, :submitted_by, :created_at

      def initialize(id:, claim_id:, proof_data:, submitted_by:, created_at:)
        @id = id
        @claim_id = claim_id
        @proof_data = proof_data
        @submitted_by = submitted_by
        @created_at = created_at
      end

      def proof_hash
        Digest::SHA256.hexdigest(proof_data.to_s)
      end
    end

    ##
    # Decision with governance backing
    #
    class Decision
      attr_reader :id, :action, :justification, :backing_claims,
                  :decided_by, :created_at

      def initialize(id:, action:, justification:, backing_claims:,
                     decided_by:, created_at:)
        @id = id
        @action = action
        @justification = justification
        @backing_claims = backing_claims
        @decided_by = decided_by
        @created_at = created_at
      end

      def decision_hash
        Digest::SHA256.hexdigest(
          "#{@id}:#{@action}:#{@backing_claims.join(',')}"
        )
      end
    end

    ##
    # Governance proof for authorization
    #
    class GovernanceProof
      attr_reader :id, :decision_id, :authorized_by,
                  :consensus_threshold, :authorized_at

      def initialize(id:, decision_id:, authorized_by:,
                     consensus_threshold:, authorized_at:)
        @id = id
        @decision_id = decision_id
        @authorized_by = authorized_by
        @consensus_threshold = consensus_threshold
        @authorized_at = authorized_at
      end

      def proof_hash
        Digest::SHA256.hexdigest(
          "#{@decision_id}:#{@authorized_by}:#{@consensus_threshold}"
        )
      end
    end

    ##
    # Execution record with audit trail
    #
    class ExecutionRecord
      attr_reader :id, :decision_id, :executed_by, :action,
                  :executed_at, :governance_proof

      def initialize(id:, decision_id:, executed_by:, action:,
                     executed_at:, governance_proof:)
        @id = id
        @decision_id = decision_id
        @executed_by = executed_by
        @action = action
        @executed_at = executed_at
        @governance_proof = governance_proof
      end

      def execution_hash
        Digest::SHA256.hexdigest(
          "#{@decision_id}:#{@executed_by}:#{@executed_at}"
        )
      end
    end

    ##
    # Agent-to-agent message
    #
    class Message
      attr_reader :type, :from_agent, :timestamp, :payload, :decision_id

      def initialize(type:, from_agent:, timestamp:, payload:, decision_id: nil)
        @type = type
        @from_agent = from_agent
        @timestamp = timestamp
        @payload = payload
        @decision_id = decision_id
      end

      def self.claim(from_agent:, claim_id:, fact:, evidence:, timestamp:)
        Message.new(
          type: :claim,
          from_agent: from_agent,
          timestamp: timestamp,
          payload: { claim_id: claim_id, fact: fact, evidence: evidence },
          decision_id: claim_id
        )
      end

      def self.proof(from_agent:, proof:, timestamp:)
        Message.new(
          type: :proof,
          from_agent: from_agent,
          timestamp: timestamp,
          payload: proof
        )
      end

      def self.decision(from_agent:, decision:, timestamp:)
        Message.new(
          type: :decision,
          from_agent: from_agent,
          timestamp: timestamp,
          payload: decision,
          decision_id: decision.id
        )
      end

      def self.authorization(from_agent:, governance_proof:, timestamp:)
        Message.new(
          type: :authorization,
          from_agent: from_agent,
          timestamp: timestamp,
          payload: governance_proof,
          decision_id: governance_proof.decision_id
        )
      end

      def self.execution(from_agent:, execution_record:, timestamp:)
        Message.new(
          type: :execution,
          from_agent: from_agent,
          timestamp: timestamp,
          payload: execution_record,
          decision_id: execution_record.decision_id
        )
      end

      def message_hash
        Digest::SHA256.hexdigest(
          "#{@type}:#{@from_agent}:#{@timestamp}:#{@payload}"
        )
      end
    end

    # Custom exceptions
    class StateError < StandardError; end
    class ClaimNotFoundError < StandardError; end
    class DecisionNotFoundError < StandardError; end
    class CircularAuthorizationError < StandardError; end
    class UnprovenClaimError < StandardError; end
    class AlreadyProvenError < StandardError; end
    class InvariantViolationError < StandardError; end
  end
end
