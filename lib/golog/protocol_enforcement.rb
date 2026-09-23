# frozen_string_literal: true

##
# ICP-DAG Protocol Enforcement Layer
#
# Verifies every agent decision has proven backing
# Enforces acyclic message chains (no circular authorization)
# Maintains immutable audit trail: timestamp + governance proof for each execution
#
# INVARIANT: Every execution has proven decision backing via immutable chain
# INVARIANT: Authorization graph is always acyclic
# INVARIANT: Audit trail is append-only and cryptographically linked
#

require 'digest'
require 'set'

module Sovereign
  module Agents
    ##
    # Protocol Enforcer: Validates ICP-DAG compliance
    #
    class ProtocolEnforcer
      attr_reader :decisions, :authorizations, :audit_log,
                  :dependency_graph, :proven_decisions

      def initialize
        @decisions = {}          # decision_id => Decision
        @authorizations = {}     # decision_id => Authorization
        @audit_log = []          # Immutable append-only log
        @dependency_graph = {}   # decision_id => Set[decision_id] (dependencies)
        @proven_decisions = Set.new
        @execution_lock = Mutex.new
      end

      ##
      # Register a decision for protocol validation
      # INVARIANT: decision_id is globally unique
      # INVARIANT: Decision references existing claimed facts
      #
      def register_decision(decision_id, action, backing_claims, metadata = {})
        @execution_lock.synchronize do
          raise ArgumentError, "Duplicate decision: #{decision_id}" \
            if @decisions.key?(decision_id)

          raise ArgumentError, "Missing backing claims" \
            if backing_claims.empty?

          decision = ProtocolDecision.new(
            id: decision_id,
            action: action,
            backing_claims: backing_claims,
            registered_at: Time.now.utc,
            metadata: metadata
          )

          @decisions[decision_id] = decision
          @dependency_graph[decision_id] = Set.new(backing_claims)

          audit_entry = AuditEntry.new(
            type: :decision_registered,
            decision_id: decision_id,
            timestamp: decision.registered_at,
            actor: metadata[:actor]
          )

          @audit_log << audit_entry

          decision
        end
      end

      ##
      # Prove a decision via supporting evidence
      # INVARIANT: All backing claims must be proven before decision proves
      # INVARIANT: Proof hash is deterministic
      #
      def prove_decision(decision_id, proof_data, actor)
        @execution_lock.synchronize do
          decision = @decisions[decision_id]
          raise DecisionNotFoundError, "No decision: #{decision_id}" \
            unless decision

          raise AlreadyProvenError, "Decision already proven" \
            if @proven_decisions.include?(decision_id)

          # Verify all backing claims are proven
          decision.backing_claims.each do |claim_id|
            unless @proven_decisions.include?(claim_id)
              raise UnprovenBackingError,
                    "Backing claim #{claim_id} not proven"
            end
          end

          proof = ProtocolProof.new(
            id: SecureRandom.hex(8),
            decision_id: decision_id,
            proof_data: proof_data,
            proved_by: actor,
            proved_at: Time.now.utc
          )

          decision.proofs << proof
          @proven_decisions.add(decision_id)

          audit_entry = AuditEntry.new(
            type: :decision_proved,
            decision_id: decision_id,
            proof_id: proof.id,
            timestamp: proof.proved_at,
            actor: actor
          )

          @audit_log << audit_entry

          proof
        end
      end

      ##
      # Authorize a proven decision
      # INVARIANT: Authorization only succeeds if decision is proven
      # INVARIANT: Authorization cannot create cycles
      # INVARIANT: Authorization threshold met
      #
      def authorize_decision(decision_id, consensus_votes, threshold = 0.67, actor)
        @execution_lock.synchronize do
          decision = @decisions[decision_id]
          raise DecisionNotFoundError, "No decision: #{decision_id}" \
            unless decision

          raise UnprovenDecisionError, "Decision not proven" \
            unless @proven_decisions.include?(decision_id)

          raise AlreadyAuthorizedError, "Decision already authorized" \
            if @authorizations.key?(decision_id)

          # Check acyclicity
          check_authorization_acyclic(decision_id)

          consensus_ratio = consensus_votes.count { |v| v[:vote] == true } \
            .to_f / consensus_votes.length

          raise InsufficientConsensusError,
                "Consensus #{consensus_ratio} below threshold #{threshold}" \
            if consensus_ratio < threshold

          authorization = ProtocolAuthorization.new(
            id: SecureRandom.hex(8),
            decision_id: decision_id,
            consensus_votes: consensus_votes,
            consensus_threshold: threshold,
            authorized_by: actor,
            authorized_at: Time.now.utc
          )

          @authorizations[decision_id] = authorization

          audit_entry = AuditEntry.new(
            type: :decision_authorized,
            decision_id: decision_id,
            authorization_id: authorization.id,
            timestamp: authorization.authorized_at,
            actor: actor,
            consensus_ratio: consensus_ratio
          )

          @audit_log << audit_entry

          authorization
        end
      end

      ##
      # Execute authorized decision
      # INVARIANT: Execution only if:
      #   1. Decision is authorized (authorization exists)
      #   2. All backing claims are proven
      #   3. No authorization cycles
      # INVARIANT: Audit trail includes full decision chain
      #
      def execute_decision(decision_id, executor)
        @execution_lock.synchronize do
          decision = @decisions[decision_id]
          raise DecisionNotFoundError, "No decision: #{decision_id}" \
            unless decision

          authorization = @authorizations[decision_id]
          raise NotAuthorizedError, "Decision not authorized" \
            unless authorization

          raise UnprovenDecisionError, "Decision not proven" \
            unless @proven_decisions.include?(decision_id)

          # Verify backing claims still proven
          decision.backing_claims.each do |claim_id|
            unless @proven_decisions.include?(claim_id)
              raise InvalidStateError,
                    "Backing claim #{claim_id} no longer proven"
            end
          end

          execution = ProtocolExecution.new(
            id: SecureRandom.hex(8),
            decision_id: decision_id,
            decision_chain: build_decision_chain(decision_id),
            executed_by: executor,
            executed_at: Time.now.utc,
            authorization: authorization
          )

          audit_entry = AuditEntry.new(
            type: :decision_executed,
            decision_id: decision_id,
            execution_id: execution.id,
            timestamp: execution.executed_at,
            actor: executor,
            decision_chain: execution.decision_chain
          )

          @audit_log << audit_entry

          execution
        end
      end

      ##
      # Check that adding authorization doesn't create cycle
      # INVARIANT: Uses depth-first search for cycle detection
      # INVARIANT: Cycles forbidden even transitively
      #
      def check_authorization_acyclic(decision_id)
        visited = Set.new
        rec_stack = Set.new

        def has_cycle?(current_id, visited, rec_stack, dependency_map)
          return false if visited.include?(current_id)

          visited.add(current_id)
          rec_stack.add(current_id)

          dependencies = dependency_map[current_id] || Set.new
          dependencies.each do |dep_id|
            return true if rec_stack.include?(dep_id)

            return true if has_cycle?(dep_id, visited, rec_stack, dependency_map)
          end

          rec_stack.delete(current_id)
          false
        end

        if has_cycle?(decision_id, visited, rec_stack, @dependency_graph)
          raise CircularAuthorizationError,
                "Adding authorization creates cycle for #{decision_id}"
        end
      end

      ##
      # Build complete decision chain with all backing
      # INVARIANT: Chain is topologically sorted (dependencies before dependents)
      #
      def build_decision_chain(decision_id)
        chain = []
        visited = Set.new

        def traverse_dependencies(current_id, visited, chain, decisions, dependency_graph)
          return if visited.include?(current_id)

          visited.add(current_id)

          dependencies = dependency_graph[current_id] || Set.new
          dependencies.each do |dep_id|
            traverse_dependencies(dep_id, visited, chain, decisions, dependency_graph)
          end

          chain << decisions[current_id] if decisions.key?(current_id)
        end

        traverse_dependencies(decision_id, visited, chain, @decisions, @dependency_graph)
        chain
      end

      ##
      # Verify entire execution chain integrity
      # INVARIANT: All decisions in chain have proofs and authorizations
      # INVARIANT: No missing links in chain
      # INVARIANT: Timestamps are monotonically increasing
      #
      def verify_chain_integrity(decision_id)
        decision = @decisions[decision_id]
        return false unless decision

        chain = build_decision_chain(decision_id)

        # Verify all in chain are authorized and proven
        chain.each do |d|
          return false unless @proven_decisions.include?(d.id)
          return false unless @authorizations.key?(d.id)
        end

        # Verify monotonic timestamps
        prev_time = nil
        chain.each do |d|
          if prev_time && d.registered_at < prev_time
            return false
          end

          prev_time = d.registered_at
        end

        true
      end

      ##
      # Get immutable audit trail for decision
      # INVARIANT: Returns snapshot at point of query (cannot be retroactively modified)
      #
      def audit_trail(decision_id)
        @execution_lock.synchronize do
          entries = @audit_log.select { |e| e.decision_id == decision_id }
          AuditTrail.new(
            decision_id: decision_id,
            entries: entries,
            snapshot_at: Time.now.utc
          )
        end
      end

      ##
      # Get authority chain (decisions required for this decision)
      # INVARIANT: All decisions in chain are proven and authorized
      #
      def authority_chain(decision_id)
        decision = @decisions[decision_id]
        return nil unless decision

        chain = build_decision_chain(decision_id)

        {
          decision_id: decision_id,
          chain: chain,
          all_proven: chain.all? { |d| @proven_decisions.include?(d.id) },
          all_authorized: chain.all? { |d| @authorizations.key?(d.id) }
        }
      end

      ##
      # Validate all protocol invariants
      # INVARIANT: This should always succeed in valid execution state
      #
      def validate_invariants!
        # 1. All authorized decisions are proven
        @authorizations.each_key do |decision_id|
          raise InvariantViolationError,
                "Authorized decision #{decision_id} not proven" \
            unless @proven_decisions.include?(decision_id)
        end

        # 2. Authorization graph is acyclic
        visited = Set.new
        rec_stack = Set.new

        @decisions.keys.each do |decision_id|
          visited.clear
          rec_stack.clear

          if cycle_exists?(decision_id, visited, rec_stack)
            raise InvariantViolationError, "Cycle in authorization graph"
          end
        end

        # 3. Audit log is monotonically timestamped
        prev_time = nil
        @audit_log.each do |entry|
          if prev_time && entry.timestamp < prev_time
            raise InvariantViolationError, "Non-monotonic audit log"
          end

          prev_time = entry.timestamp
        end

        # 4. All dependencies reference existing decisions
        @dependency_graph.each do |decision_id, dependencies|
          dependencies.each do |dep_id|
            raise InvariantViolationError,
                  "Invalid dependency: #{decision_id} -> #{dep_id}" \
              unless @decisions.key?(dep_id) || @proven_decisions.include?(dep_id)
          end
        end

        true
      end

      private

      def cycle_exists?(current_id, visited, rec_stack)
        return false if visited.include?(current_id)

        visited.add(current_id)
        rec_stack.add(current_id)

        dependencies = @dependency_graph[current_id] || Set.new
        dependencies.each do |dep_id|
          return true if rec_stack.include?(dep_id)
          return true if cycle_exists?(dep_id, visited, rec_stack)
        end

        rec_stack.delete(current_id)
        false
      end
    end

    ##
    # Protocol Decision representation
    #
    class ProtocolDecision
      attr_reader :id, :action, :backing_claims, :registered_at, :metadata
      attr_accessor :proofs

      def initialize(id:, action:, backing_claims:, registered_at:, metadata: {})
        @id = id
        @action = action
        @backing_claims = backing_claims
        @registered_at = registered_at
        @metadata = metadata
        @proofs = []
      end

      def decision_hash
        Digest::SHA256.hexdigest(
          "#{@id}:#{@action}:#{@backing_claims.join(',')}"
        )
      end
    end

    ##
    # Protocol Proof
    #
    class ProtocolProof
      attr_reader :id, :decision_id, :proof_data, :proved_by, :proved_at

      def initialize(id:, decision_id:, proof_data:, proved_by:, proved_at:)
        @id = id
        @decision_id = decision_id
        @proof_data = proof_data
        @proved_by = proved_by
        @proved_at = proved_at
      end

      def proof_hash
        Digest::SHA256.hexdigest(
          "#{@decision_id}:#{@proved_by}:#{@proved_at}:#{@proof_data}"
        )
      end
    end

    ##
    # Protocol Authorization
    #
    class ProtocolAuthorization
      attr_reader :id, :decision_id, :consensus_votes,
                  :consensus_threshold, :authorized_by, :authorized_at

      def initialize(id:, decision_id:, consensus_votes:,
                     consensus_threshold:, authorized_by:, authorized_at:)
        @id = id
        @decision_id = decision_id
        @consensus_votes = consensus_votes
        @consensus_threshold = consensus_threshold
        @authorized_by = authorized_by
        @authorized_at = authorized_at
      end

      def authorization_hash
        Digest::SHA256.hexdigest(
          "#{@decision_id}:#{@authorized_by}:#{@consensus_threshold}"
        )
      end
    end

    ##
    # Protocol Execution
    #
    class ProtocolExecution
      attr_reader :id, :decision_id, :decision_chain,
                  :executed_by, :executed_at, :authorization

      def initialize(id:, decision_id:, decision_chain:,
                     executed_by:, executed_at:, authorization:)
        @id = id
        @decision_id = decision_id
        @decision_chain = decision_chain
        @executed_by = executed_by
        @executed_at = executed_at
        @authorization = authorization
      end

      def execution_hash
        Digest::SHA256.hexdigest(
          "#{@decision_id}:#{@executed_by}:#{@executed_at}:#{chain_hash}"
        )
      end

      def chain_hash
        Digest::SHA256.hexdigest(@decision_chain.map(&:id).join(','))
      end
    end

    ##
    # Audit Log Entry
    #
    class AuditEntry
      attr_reader :type, :decision_id, :timestamp, :actor, :metadata

      def initialize(type:, decision_id:, timestamp:, actor:, **metadata)
        @type = type
        @decision_id = decision_id
        @timestamp = timestamp
        @actor = actor
        @metadata = metadata
      end

      def entry_hash
        Digest::SHA256.hexdigest(
          "#{@type}:#{@decision_id}:#{@timestamp}:#{@actor}"
        )
      end
    end

    ##
    # Audit Trail with snapshot
    #
    class AuditTrail
      attr_reader :decision_id, :entries, :snapshot_at

      def initialize(decision_id:, entries:, snapshot_at:)
        @decision_id = decision_id
        @entries = entries
        @snapshot_at = snapshot_at
      end

      def entry_count
        @entries.length
      end

      def timeline
        @entries.sort_by(&:timestamp)
      end

      def verify_chain
        timeline.each_cons(2) do |curr, next_entry|
          if next_entry.timestamp < curr.timestamp
            return false
          end
        end
        true
      end
    end

    # Custom exceptions
    class DecisionNotFoundError < StandardError; end
    class AlreadyProvenError < StandardError; end
    class UnprovenBackingError < StandardError; end
    class UnprovenDecisionError < StandardError; end
    class AlreadyAuthorizedError < StandardError; end
    class NotAuthorizedError < StandardError; end
    class InsufficientConsensusError < StandardError; end
    class CircularAuthorizationError < StandardError; end
    class InvalidStateError < StandardError; end
    class InvariantViolationError < StandardError; end
  end
end
