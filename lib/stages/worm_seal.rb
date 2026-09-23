# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::stages::worm_seal
# frozen_string_literal: true

require_relative '../kernel/worm'

module Sovereign
  module Stages
    module WormSeal
      def self.run(kernel, clj_result:, apl_result:, axiom_result:)
        kernel.verify!

        payload = {
          stack:          'Ruby → Clojure → APL → AXIOM → WORM',
          trs:            kernel.evaluate.round(6),
          norm:           kernel.norm.round(6),
          canonical:      Kernel::SymbolicKernel::CANONICAL_TRS,
          apl_match:      apl_result[:match],
          axiom_verified: axiom_result[:verified],
          chain_length:   Kernel::WORM.length,
          chain_valid:    Kernel::WORM.valid?,
          tree_depth:     kernel.tree.depth,
          book:           'BOW-Ω-φ-∂-2026'
        }

        final = Kernel::WORM.seal('SOVEREIGN-FINAL', payload)
        kernel.seal!

        {
          seal: final[:seal],
          payload: payload,
          chain_valid: Kernel::WORM.valid?,
          governance_state: kernel.gate.state
        }
      end
    end
  end
end
