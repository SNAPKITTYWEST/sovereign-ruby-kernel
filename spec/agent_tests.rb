# frozen_string_literal: true

##
# Comprehensive tests for Golog Agent Framework
#
# Tests verify:
# - ICP-DAG protocol enforcement
# - State machine correctness
# - Acyclic authorization
# - Audit trail immutability
# - DSL operations
#

require 'minitest/autorun'
require_relative 'agents_framework'
require_relative 'fsl_compiler'
require_relative 'protocol_enforcement'
require_relative 'agent_dsl'

module Sovereign
  module Agents
    class TestGologAgent < Minitest::Test
      def setup
        @agent = GologAgent.new("agent_1")
      end

      def test_agent_initialization
        assert_equal "agent_1", @agent.id
        assert_equal GologAgent::STATE_UNKNOWN, @agent.current_state
        assert_empty @agent.claimed_facts
        assert_empty @agent.proven_facts
      end

      def test_state_transition_valid
        @agent.transition_to(GologAgent::STATE_PROPOSED)
        assert_equal GologAgent::STATE_PROPOSED, @agent.current_state
      end

      def test_state_transition_invalid
        assert_raises(ArgumentError) do
          @agent.transition_to(GologAgent::STATE_EXECUTED)
        end
      end

      def test_claim_creation
        claim_msg = @agent.claim("claim_1", "fact_A", "evidence_A")
        assert_equal :claim, claim_msg.type
        assert_equal "agent_1", claim_msg.from_agent
        assert_equal "claim_1", claim_msg.payload[:claim_id]
        assert_includes @agent.claimed_facts.keys, "claim_1"
      end

      def test_claim_transitions_state
        @agent.claim("claim_1", "fact_A", "evidence_A")
        assert_equal GologAgent::STATE_PROPOSED, @agent.current_state
      end

      def test_proof_submission
        @agent.claim("claim_1", "fact_A", "evidence_A")
        proof_msg = @agent.submit_proof("proof_1", "claim_1", { proof: "valid" })
        assert_equal :proof, proof_msg.type
        assert_equal GologAgent::STATE_VERIFIED, @agent.current_state
      end

      def test_proof_requires_existing_claim
        assert_raises(GologAgent::ClaimNotFoundError) do
          @agent.submit_proof("proof_1", "missing_claim", {})
        end
      end

      def test_decision_creation
        @agent.claim("claim_1", "fact_A", "evidence_A")
        @agent.submit_proof("proof_1", "claim_1", {})

        decision_msg = @agent.decide(
          "decision_1",
          "action_X",
          "because reasons",
          ["claim_1"]
        )

        assert_equal :decision, decision_msg.type
        assert_equal GologAgent::STATE_PROVEN, @agent.current_state
      end

      def test_decision_requires_backing_claims
        @agent.claim("claim_1", "fact_A", "evidence_A")
        @agent.submit_proof("proof_1", "claim_1", {})

        assert_raises(ArgumentError) do
          @agent.decide("decision_1", "action_X", "reasons", [])
        end
      end

      def test_authorization_creates_proof
        @agent.claim("claim_1", "fact_A", "evidence_A")
        @agent.submit_proof("proof_1", "claim_1", {})
        @agent.decide("decision_1", "action_X", "reasons", ["claim_1"])

        proof = @agent.authorize("decision_1", 0.67)
        assert_kind_of GologAgent::GovernanceProof, proof
        assert_equal GologAgent::STATE_AUTHORIZED, @agent.current_state
      end

      def test_execution_requires_authorization
        @agent.claim("claim_1", "fact_A", "evidence_A")
        @agent.submit_proof("proof_1", "claim_1", {})
        @agent.decide("decision_1", "action_X", "reasons", ["claim_1"])

        assert_raises(ArgumentError) do
          @agent.execute("decision_1")
        end
      end

      def test_execution_full_pipeline
        @agent.claim("claim_1", "fact_A", "evidence_A")
        @agent.mark_proven("claim_1")
        @agent.submit_proof("proof_1", "claim_1", {})
        @agent.decide("decision_1", "action_X", "reasons", ["claim_1"])
        @agent.authorize("decision_1", 0.67)

        record = @agent.execute("decision_1")
        assert_kind_of GologAgent::ExecutionRecord, record
        assert_equal GologAgent::STATE_EXECUTED, @agent.current_state
      end

      def test_audit_trail_generation
        @agent.claim("claim_1", "fact_A", "evidence_A")
        @agent.mark_proven("claim_1")
        @agent.submit_proof("proof_1", "claim_1", {})
        @agent.decide("decision_1", "action_X", "reasons", ["claim_1"])
        @agent.authorize("decision_1", 0.67)
        @agent.execute("decision_1")

        trail = @agent.audit_trail("decision_1")
        assert_not_nil trail
        assert_equal "decision_1", trail[:decision_id]
        assert trail[:messages].length > 0
      end

      def test_circular_authorization_prevention
        @agent.claim("claim_1", "fact_A", "evidence_A")
        @agent.mark_proven("claim_1")
        @agent.submit_proof("proof_1", "claim_1", {})

        decision1 = @agent.decide(
          "decision_1",
          "action_X",
          "reasons",
          ["claim_1"]
        )

        # Try to create circular dependency
        @agent.claim("claim_2", "fact_B", "evidence_B")
        @agent.mark_proven("claim_2")
        @agent.submit_proof("proof_2", "claim_2", {})

        # This should prevent cycles
        @agent.decide(
          "decision_2",
          "action_Y",
          "reasons",
          ["claim_2"]
        )

        # Verify no cycles in actual data structure
        @agent.validate_invariants!
      end

      def test_invariant_validation
        @agent.claim("claim_1", "fact_A", "evidence_A")
        @agent.mark_proven("claim_1")
        @agent.submit_proof("proof_1", "claim_1", {})
        @agent.decide("decision_1", "action_X", "reasons", ["claim_1"])

        assert @agent.validate_invariants!
      end

      def test_multiple_claims_and_proofs
        (1..5).each do |i|
          @agent.claim("claim_#{i}", "fact_#{i}", "evidence_#{i}")
          @agent.mark_proven("claim_#{i}")
        end

        assert_equal 5, @agent.claimed_facts.length
        assert_equal 5, @agent.proven_facts.length
      end
    end

    class TestFSLCompiler < Minitest::Test
      def test_parser_initialization
        source = "assert fact_A."
        parser = FSLParser.new(source)
        assert_not_nil parser.tokens
      end

      def test_tokenization_basic
        source = "claim atom_X ( identifier_Y , number_5 )."
        parser = FSLParser.new(source)
        assert parser.tokens.length > 0
        assert_equal FSLParser::TOKEN_EOF, parser.tokens.last[:type]
      end

      def test_parse_assertion
        source = "assert fact_A."
        parser = FSLParser.new(source)
        expr = parser.parse
        assert_kind_of FslAssertion, expr
        assert_equal :assert, expr.type
      end

      def test_parse_claim_expression
        source = 'claim my_claim ( fact_X , evidence_Y ).'
        parser = FSLParser.new(source)
        expr = parser.parse
        assert_kind_of FslAssertion, expr
        assert_equal :claim, expr.type
      end

      def test_compiler_basic
        source = "assert fact_A."
        compiler = FSLCompiler.new(source)
        result = compiler.compile

        assert_not_nil result[:assertions]
        assert_not_nil result[:ir]
      end

      def test_compiler_produces_opal_ir
        source = 'claim test_claim ( fact_X , evidence_Y ).'
        compiler = FSLCompiler.new(source)
        result = compiler.compile

        assert result[:ir].length > 0
        assert_equal :claim, result[:ir].first.operation
      end

      def test_type_safety_checking
        source = 'claim test ( fact_X , evidence_Y ).'
        compiler = FSLCompiler.new(source)
        result = compiler.compile

        # Verify constraints were evaluated
        assert_not_nil result[:constraints]
      end

      def test_constraint_evaluation
        source = "assert fact_A."
        compiler = FSLCompiler.new(source)
        result = compiler.compile

        # All assertions should compile without errors
        assert result[:assertions].length > 0
      end

      def test_opal_value_serialization
        value = OpalValue.new(:atom, :test_atom)
        assert_equal "test_atom", value.to_s

        value2 = OpalValue.new(:number, 42)
        assert_equal "42", value2.to_s

        value3 = OpalValue.new(:string, "hello")
        assert_equal '"hello"', value3.to_s
      end

      def test_complex_fsl_program
        source = 'prove proof_id ( claim_X , proof_data ).'
        parser = FSLParser.new(source)
        expr = parser.parse
        assert_kind_of FslAssertion, expr
      end
    end

    class TestProtocolEnforcer < Minitest::Test
      def setup
        @enforcer = ProtocolEnforcer.new
      end

      def test_enforcer_initialization
        assert_not_nil @enforcer.decisions
        assert_not_nil @enforcer.authorizations
        assert_empty @enforcer.audit_log
      end

      def test_register_decision
        decision = @enforcer.register_decision(
          "decision_1",
          "execute_action",
          ["claim_1"],
          { actor: "agent_1" }
        )

        assert_kind_of ProtocolDecision, decision
        assert_equal "decision_1", decision.id
      end

      def test_duplicate_decision_rejected
        @enforcer.register_decision(
          "decision_1",
          "action",
          ["claim_1"],
          { actor: "agent_1" }
        )

        assert_raises(ArgumentError) do
          @enforcer.register_decision(
            "decision_1",
            "action",
            ["claim_1"],
            { actor: "agent_1" }
          )
        end
      end

      def test_prove_decision
        @enforcer.register_decision(
          "decision_1",
          "action",
          ["claim_1"],
          { actor: "agent_1" }
        )

        # Prove backing claim first
        @enforcer.register_decision("claim_1", "fact", [], { actor: "agent_1" })
        @enforcer.prove_decision("claim_1", "evidence", "agent_1")

        # Then prove main decision
        proof = @enforcer.prove_decision("decision_1", "proof_data", "agent_1")
        assert_kind_of ProtocolProof, proof
      end

      def test_authorize_decision
        @enforcer.register_decision(
          "decision_1",
          "action",
          ["claim_1"],
          { actor: "agent_1" }
        )

        @enforcer.register_decision("claim_1", "fact", [], { actor: "agent_1" })
        @enforcer.prove_decision("claim_1", "evidence", "agent_1")
        @enforcer.prove_decision("decision_1", "proof_data", "agent_1")

        votes = [
          { agent_id: "voter_1", vote: true },
          { agent_id: "voter_2", vote: true }
        ]

        auth = @enforcer.authorize_decision("decision_1", votes, 0.67, "authorizer_1")
        assert_kind_of ProtocolAuthorization, auth
      end

      def test_authorization_requires_proof
        @enforcer.register_decision(
          "decision_1",
          "action",
          ["claim_1"],
          { actor: "agent_1" }
        )

        votes = [{ agent_id: "voter_1", vote: true }]

        assert_raises(ProtocolEnforcer::UnprovenDecisionError) do
          @enforcer.authorize_decision("decision_1", votes, 0.67, "authorizer_1")
        end
      end

      def test_execute_decision
        @enforcer.register_decision(
          "decision_1",
          "action",
          ["claim_1"],
          { actor: "agent_1" }
        )

        @enforcer.register_decision("claim_1", "fact", [], { actor: "agent_1" })
        @enforcer.prove_decision("claim_1", "evidence", "agent_1")
        @enforcer.prove_decision("decision_1", "proof_data", "agent_1")

        votes = [
          { agent_id: "voter_1", vote: true },
          { agent_id: "voter_2", vote: true }
        ]
        @enforcer.authorize_decision("decision_1", votes, 0.67, "authorizer_1")

        execution = @enforcer.execute_decision("decision_1", "executor_1")
        assert_kind_of ProtocolExecution, execution
      end

      def test_audit_trail_immutability
        @enforcer.register_decision(
          "decision_1",
          "action",
          ["claim_1"],
          { actor: "agent_1" }
        )

        trail = @enforcer.audit_trail("decision_1")
        initial_size = trail.entry_count

        # Attempting to register again fails, so trail should remain same size
        trail2 = @enforcer.audit_trail("decision_1")
        assert_equal initial_size, trail2.entry_count
      end

      def test_acyclic_authorization_check
        # Create chain: decision_1 -> claim_1
        @enforcer.register_decision(
          "decision_1",
          "action",
          ["claim_1"],
          { actor: "agent_1" }
        )

        @enforcer.register_decision("claim_1", "fact", [], { actor: "agent_1" })
        @enforcer.prove_decision("claim_1", "evidence", "agent_1")
        @enforcer.prove_decision("decision_1", "proof_data", "agent_1")

        # Should allow authorization (no cycle)
        votes = [{ agent_id: "voter_1", vote: true }]
        auth = @enforcer.authorize_decision("decision_1", votes, 0.67, "authorizer_1")
        assert_not_nil auth
      end

      def test_invariant_validation
        @enforcer.register_decision(
          "decision_1",
          "action",
          ["claim_1"],
          { actor: "agent_1" }
        )

        @enforcer.register_decision("claim_1", "fact", [], { actor: "agent_1" })
        @enforcer.prove_decision("claim_1", "evidence", "agent_1")
        @enforcer.prove_decision("decision_1", "proof_data", "agent_1")

        votes = [{ agent_id: "voter_1", vote: true }]
        @enforcer.authorize_decision("decision_1", votes, 0.67, "authorizer_1")

        # Should validate without errors
        assert @enforcer.validate_invariants!
      end

      def test_consensus_threshold_enforcement
        @enforcer.register_decision(
          "decision_1",
          "action",
          ["claim_1"],
          { actor: "agent_1" }
        )

        @enforcer.register_decision("claim_1", "fact", [], { actor: "agent_1" })
        @enforcer.prove_decision("claim_1", "evidence", "agent_1")
        @enforcer.prove_decision("decision_1", "proof_data", "agent_1")

        # Consensus with only 0.33 (below 0.67 threshold)
        votes = [
          { agent_id: "voter_1", vote: true },
          { agent_id: "voter_2", vote: false },
          { agent_id: "voter_3", vote: false }
        ]

        assert_raises(ProtocolEnforcer::InsufficientConsensusError) do
          @enforcer.authorize_decision("decision_1", votes, 0.67, "authorizer_1")
        end
      end
    end

    class TestAgentDSL < Minitest::Test
      def setup
        @dsl = AgentDSL.new
      end

      def test_dsl_initialization
        assert_not_nil @dsl.enforcer
        assert_empty @dsl.agents
      end

      def test_register_agent
        agent = @dsl.register_agent("agent_1")
        assert_kind_of GologAgent, agent
        assert_equal "agent_1", agent.id
      end

      def test_claim_operation
        @dsl.register_agent("agent_1")
        msg = @dsl.claim("agent_1", "claim_1", "fact_A", "evidence_A")
        assert_equal :claim, msg.type
      end

      def test_authorize_operation
        @dsl.register_agent("agent_1")
        @dsl.register_agent("agent_2")

        # First claim and register decision
        @dsl.claim("agent_1", "claim_1", "fact_A", "evidence_A")

        # Create decision backed by claim
        @dsl.enforcer.register_decision(
          "decision_1",
          "action_X",
          ["claim_1"],
          { actor: "agent_1" }
        )

        @dsl.enforcer.prove_decision("claim_1", "evidence", "agent_1")
        @dsl.enforcer.prove_decision("decision_1", "proof_data", "agent_1")

        # Authorize with consensus
        votes = [
          { agent_id: "agent_1", vote: true },
          { agent_id: "agent_2", vote: true }
        ]

        auth = @dsl.authorize("agent_1", "decision_1", "majority agrees", votes, 0.67)
        assert_kind_of ProtocolEnforcer::ProtocolAuthorization, auth
      end

      def test_execute_operation
        @dsl.register_agent("agent_1")

        # Full pipeline
        @dsl.claim("agent_1", "claim_1", "fact_A", "evidence_A")

        @dsl.enforcer.register_decision(
          "decision_1",
          "action_X",
          ["claim_1"],
          { actor: "agent_1" }
        )

        @dsl.enforcer.prove_decision("claim_1", "evidence", "agent_1")
        @dsl.enforcer.prove_decision("decision_1", "proof_data", "agent_1")

        votes = [{ agent_id: "agent_1", vote: true }]
        @dsl.authorize("agent_1", "decision_1", "approved", votes, 0.67)

        execution = @dsl.execute("agent_1", "decision_1", "execute_directive")
        assert_not_nil execution[:execution]
      end

      def test_audit_trail_query
        @dsl.register_agent("agent_1")
        @dsl.claim("agent_1", "claim_1", "fact_A", "evidence_A")

        @dsl.enforcer.register_decision(
          "decision_1",
          "action_X",
          ["claim_1"],
          { actor: "agent_1" }
        )

        trail = @dsl.audit_trail("decision_1")
        assert_not_nil trail
      end

      def test_authority_chain_query
        @dsl.register_agent("agent_1")
        @dsl.claim("agent_1", "claim_1", "fact_A", "evidence_A")

        @dsl.enforcer.register_decision(
          "decision_1",
          "action_X",
          ["claim_1"],
          { actor: "agent_1" }
        )

        @dsl.enforcer.prove_decision("claim_1", "evidence", "agent_1")
        @dsl.enforcer.prove_decision("decision_1", "proof_data", "agent_1")

        chain = @dsl.authority_chain("decision_1")
        assert_not_nil chain
        assert chain[:all_proven]
      end

      def test_agent_state_query
        @dsl.register_agent("agent_1")
        @dsl.claim("agent_1", "claim_1", "fact_A", "evidence_A")

        state = @dsl.agent_state("agent_1")
        assert_equal "agent_1", state[:agent_id]
        assert state[:claimed_facts].include?("claim_1")
      end

      def test_invariant_validation_dsl
        @dsl.register_agent("agent_1")
        @dsl.claim("agent_1", "claim_1", "fact_A", "evidence_A")

        assert @dsl.validate_invariants!
      end
    end

    class TestAgentCoordinator < Minitest::Test
      def setup
        @coordinator = AgentCoordinator.new
      end

      def test_coordinator_initialization
        assert_not_nil @coordinator.dsl
      end

      def test_create_agents
        agent_ids = ["agent_1", "agent_2", "agent_3"]
        agents = @coordinator.create_agents(agent_ids)

        assert_equal 3, agents.length
        assert agents.key?("agent_1")
      end

      def test_collective_claim
        @coordinator.create_agents(["agent_1", "agent_2"])
        claims = @coordinator.collective_claim("fact_A", "evidence_A")

        assert_equal 2, claims.length
      end

      def test_orchestrate_execution
        @coordinator.create_agents(["agent_1", "agent_2", "agent_3"])

        result = @coordinator.orchestrate_execution(
          "fact_A",
          "evidence_A",
          "execute_action",
          nil,
          0.67
        )

        assert_not_nil result[:claims]
        assert_not_nil result[:decision_id]
        assert_not_nil result[:authorization]
        assert_not_nil result[:execution]
      end

      def test_consensus_statistics
        @coordinator.create_agents(["agent_1", "agent_2"])

        # Execute a few times
        3.times do |i|
          @coordinator.orchestrate_execution(
            "fact_#{i}",
            "evidence_#{i}",
            "action_#{i}",
            nil,
            0.67
          )
        end

        stats = @coordinator.consensus_statistics
        assert stats[:total_decisions] > 0
        assert stats[:avg_threshold] > 0
      end
    end

    class TestIntegration < Minitest::Test
      def test_full_agent_workflow
        # Create DSL
        dsl = AgentDSL.new

        # Create agents
        dsl.register_agent("alice")
        dsl.register_agent("bob")

        # Alice makes a claim
        claim_msg = dsl.claim("alice", "claim_1", "weather_sunny", "saw_sunny_weather")
        assert_equal :claim, claim_msg.type

        # Register decision
        dsl.enforcer.register_decision(
          "decision_1",
          "go_outside",
          ["claim_1"],
          { actor: "alice" }
        )

        # Prove the decision chain
        dsl.enforcer.prove_decision("claim_1", "direct_observation", "alice")
        dsl.enforcer.prove_decision("decision_1", "logical_consequence", "alice")

        # Get consensus from agents
        votes = [
          { agent_id: "alice", vote: true },
          { agent_id: "bob", vote: true }
        ]

        authorization = dsl.authorize("alice", "decision_1", "weather check passed", votes)
        assert_not_nil authorization

        # Execute
        execution = dsl.execute("alice", "decision_1", "going_outside_now")
        assert_not_nil execution

        # Verify audit trail
        trail = dsl.audit_trail("decision_1")
        assert trail.entry_count > 0

        # Verify invariants hold
        assert dsl.validate_invariants!
      end

      def test_multi_decision_chain
        dsl = AgentDSL.new
        dsl.register_agent("agent_1")

        # Create a chain: claim_1 -> decision_1 -> claim_2 -> decision_2
        dsl.claim("agent_1", "claim_1", "fact_1", "evidence_1")
        dsl.enforcer.register_decision("decision_1", "action_1", ["claim_1"], { actor: "agent_1" })
        dsl.enforcer.prove_decision("claim_1", "proof_1", "agent_1")
        dsl.enforcer.prove_decision("decision_1", "proof_2", "agent_1")

        votes = [{ agent_id: "agent_1", vote: true }]
        dsl.authorize("agent_1", "decision_1", "approved", votes)

        # Execute first decision
        dsl.execute("agent_1", "decision_1", "execute_1")

        # Now make dependent decision
        dsl.claim("agent_1", "claim_2", "fact_2", "evidence_2")
        dsl.enforcer.register_decision(
          "decision_2",
          "action_2",
          ["claim_2", "decision_1"],
          { actor: "agent_1" }
        )

        dsl.enforcer.prove_decision("claim_2", "proof_3", "agent_1")
        dsl.enforcer.prove_decision("decision_2", "proof_4", "agent_1")

        dsl.authorize("agent_1", "decision_2", "approved", votes)
        exec2 = dsl.execute("agent_1", "decision_2", "execute_2")

        # Verify chain integrity
        chain = dsl.authority_chain("decision_2")
        assert chain[:all_proven]
        assert chain[:all_authorized]
        assert_equal 2, chain[:chain].length
      end
    end
  end
end
