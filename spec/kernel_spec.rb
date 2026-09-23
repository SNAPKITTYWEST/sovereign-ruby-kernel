# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::spec::kernel_spec
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'kernel/symbolic_kernel'
require 'kernel/worm'
require 'kernel/governance'
require 'ast/node'
require 'ast/phi_algebra'
require 'ast/rewrite'
require 'stages/clojure_trs'
require 'stages/apl_verify'
require 'stages/axiom_proof'
require 'stages/worm_seal'
require 'swarm/agent'
require 'swarm/topology'
require 'swarm/self_synthesis'

module TestRunner
  @pass = 0
  @fail = 0

  def self.test(name)
    yield
    @pass += 1
    puts "  PASS  #{name}"
  rescue => e
    @fail += 1
    puts "  FAIL  #{name}: #{e.message}"
  end

  def self.assert(cond, msg = 'assertion failed')
    raise msg unless cond
  end

  def self.assert_equal(expected, actual, msg = nil)
    raise "#{msg || 'not equal'}: expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
  end

  def self.summary
    puts "\n#{@pass + @fail} tests: #{@pass} passed, #{@fail} failed"
    exit(@fail > 0 ? 1 : 0)
  end
end

puts "=== Sovereign Ruby Kernel Tests ==="

Sovereign::Kernel::WORM.reset!

# ── AST Tests ──

TestRunner.test('Node creation') do
  n = Sovereign::AST::Node.new(:test, children: [1, 2])
  TestRunner.assert_equal :test, n.type
  TestRunner.assert_equal 2, n.arity
  TestRunner.assert !n.leaf?
end

TestRunner.test('Node leaf') do
  n = Sovereign::AST::Node.new(:leaf)
  TestRunner.assert n.leaf?
  TestRunner.assert_equal 0, n.depth
end

TestRunner.test('Node to_sexp') do
  n = Sovereign::AST::PhiAlgebra.add(
    Sovereign::AST::PhiAlgebra.literal(1),
    Sovereign::AST::PhiAlgebra.phi(2)
  )
  s = n.to_sexp
  TestRunner.assert s.include?('add')
  TestRunner.assert s.include?('lit')
  TestRunner.assert s.include?('phi')
end

TestRunner.test('Phi evaluation') do
  phi = Sovereign::AST::PHI
  node = Sovereign::AST::PhiAlgebra.phi(3)
  val = Sovereign::AST::PhiAlgebra.evaluate(node)
  TestRunner.assert (val - phi**3).abs < 0.0001
end

TestRunner.test('Galois conjugate swaps phi/phi_hat') do
  node = Sovereign::AST::PhiAlgebra.phi(2)
  conj = Sovereign::AST::PhiAlgebra.galois_conjugate(node)
  TestRunner.assert_equal :phi_hat, conj.type
end

TestRunner.test('TRS tree builds correctly') do
  tree = Sovereign::AST::PhiAlgebra.trs_tree([0, 1], { A: [1.0, 1.0] })
  TestRunner.assert_equal :trs, tree.type
  TestRunner.assert tree.depth > 0
end

TestRunner.test('Rewrite normalize runs') do
  tree = Sovereign::AST::PhiAlgebra.add(
    Sovereign::AST::PhiAlgebra.literal(0),
    Sovereign::AST::PhiAlgebra.phi(1)
  )
  result = Sovereign::AST::Rewrite.normalize(tree)
  TestRunner.assert result.key?(:normal_form)
  TestRunner.assert result.key?(:trace)
end

# ── Kernel Tests ──

TestRunner.test('SymbolicKernel evaluates to canonical TRS') do
  k = Sovereign::Kernel::SymbolicKernel.new
  trs = k.evaluate
  TestRunner.assert (trs - 388.985128).abs < 0.01, "TRS=#{trs}"
end

TestRunner.test('SymbolicKernel norm is rational') do
  k = Sovereign::Kernel::SymbolicKernel.new
  n = k.norm
  TestRunner.assert n.is_a?(Float)
  TestRunner.assert n.finite?
end

TestRunner.test('SymbolicKernel verify succeeds') do
  k = Sovereign::Kernel::SymbolicKernel.new
  evidence = k.verify!
  TestRunner.assert_equal :verified, k.gate.state
  TestRunner.assert evidence[:delta] < 0.001
end

TestRunner.test('SymbolicKernel seal succeeds') do
  k = Sovereign::Kernel::SymbolicKernel.new
  seal = k.seal!
  TestRunner.assert seal.is_a?(String)
  TestRunner.assert_equal 64, seal.length
  TestRunner.assert_equal :sealed, k.gate.state
end

TestRunner.test('AST forest has all symbols') do
  k = Sovereign::Kernel::SymbolicKernel.new
  forest = k.to_ast_forest
  TestRunner.assert_equal 4, forest[:symbols].size
  TestRunner.assert forest[:symbols].key?(:ME)
  TestRunner.assert forest[:symbols].key?(:DINGIR)
end

# ── WORM Tests ──

TestRunner.test('WORM chain is valid') do
  Sovereign::Kernel::WORM.reset!
  Sovereign::Kernel::WORM.seal('test1', { a: 1 })
  Sovereign::Kernel::WORM.seal('test2', { b: 2 })
  Sovereign::Kernel::WORM.seal('test3', { c: 3 })
  TestRunner.assert Sovereign::Kernel::WORM.valid?
  TestRunner.assert_equal 3, Sovereign::Kernel::WORM.length
end

TestRunner.test('WORM verify_entry') do
  Sovereign::Kernel::WORM.reset!
  Sovereign::Kernel::WORM.seal('v1', { x: 42 })
  TestRunner.assert Sovereign::Kernel::WORM.verify_entry(0)
end

# ── Governance Tests ──

TestRunner.test('Governance state transitions') do
  g = Sovereign::Kernel::Governance.new_gate
  TestRunner.assert_equal :init, g.state
  g.transition!(:verified, evidence: { proof: true })
  TestRunner.assert_equal :verified, g.state
  g.transition!(:sealed)
  TestRunner.assert g.sealed?
end

TestRunner.test('Governance rejects invalid transitions') do
  g = Sovereign::Kernel::Governance.new_gate
  begin
    g.transition!(:sealed)
    raise 'Should have raised'
  rescue Sovereign::Kernel::Governance::StateError
    # expected
  end
end

# ── Stage Tests ──

TestRunner.test('ClojureTRS stage runs inline') do
  Sovereign::Kernel::WORM.reset!
  k = Sovereign::Kernel::SymbolicKernel.new
  r = Sovereign::Stages::ClojureTRS.run(k)
  TestRunner.assert_equal :inline, r[:source]
  TestRunner.assert (r[:trs] - 388.985128).abs < 0.01
end

TestRunner.test('APLVerify stage matches') do
  Sovereign::Kernel::WORM.reset!
  k = Sovereign::Kernel::SymbolicKernel.new
  r = Sovereign::Stages::APLVerify.run(k)
  TestRunner.assert r[:match]
end

TestRunner.test('AxiomProof stage verifies via rewrite') do
  Sovereign::Kernel::WORM.reset!
  k = Sovereign::Kernel::SymbolicKernel.new
  r = Sovereign::Stages::AxiomProof.run(k)
  TestRunner.assert_equal :rewrite_engine, r[:source]
end

# ── Swarm Tests ──

TestRunner.test('Swarm agent creation') do
  a = Sovereign::Swarm::Agent.new(id: :test, role: :parser)
  TestRunner.assert_equal :idle, a.state
  TestRunner.assert_equal :parser, a.role
end

TestRunner.test('Swarm topology builds pipeline') do
  topo = Sovereign::Swarm::Topology.sovereign_pipeline
  TestRunner.assert_equal 11, topo.agents.size
  TestRunner.assert topo.edges.size >= 10
end

TestRunner.test('Swarm topology emits DOT') do
  topo = Sovereign::Swarm::Topology.sovereign_pipeline
  dot = topo.to_dot
  TestRunner.assert dot.include?('digraph')
  TestRunner.assert dot.include?('scout_0')
  TestRunner.assert dot.include?('seal_0')
end

# ── Self Synthesis Tests ──

TestRunner.test('Self synthesis emits object') do
  k = Sovereign::Kernel::SymbolicKernel.new
  code = Sovereign::Swarm::SelfSynthesis.emit_module(k)
  TestRunner.assert code.include?('trs')
  TestRunner.assert code.include?('verify')
  TestRunner.assert code.include?('value')
  TestRunner.assert code.length > 100
end

TestRunner.test('Self synthesis emits leaf') do
  leaf = Sovereign::AST::PhiAlgebra.literal(42)
  out = Sovereign::Swarm::SelfSynthesis.emit(leaf)
  TestRunner.assert out.include?('#lit')
  TestRunner.assert out.include?('42')
end

TestRunner.summary
