# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::stages::axiom_proof
# frozen_string_literal: true

require 'open3'
require_relative '../kernel/worm'

module Sovereign
  module Stages
    module AxiomProof
      def self.run(kernel, proof_file: nil)
        if proof_file && File.exist?(proof_file)
          content = File.read(proof_file)
          sorry_count = content.scan(/sorry/).count
          result = {
            proof: proof_file,
            sorry_count: sorry_count,
            verified: sorry_count == 0,
            source: :file
          }
        else
          nf = kernel.normalize
          result = {
            confluent: AST::Rewrite.confluent?(kernel.tree),
            rewrite_steps: nf[:trace].length,
            normal_form: nf[:normal_form].to_sexp[0..200],
            verified: AST::Rewrite.confluent?(kernel.tree),
            source: :rewrite_engine
          }
        end

        Kernel::WORM.seal('stage:axiom', result)
        result
      end
    end
  end
end
