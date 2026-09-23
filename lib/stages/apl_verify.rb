# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::stages::apl_verify
# frozen_string_literal: true

require_relative '../kernel/worm'
require_relative '../ast/phi_algebra'

module Sovereign
  module Stages
    module APLVerify
      def self.run(kernel)
        forest = kernel.to_ast_forest
        per_symbol = forest[:symbols].map do |sym, subtree|
          [sym, AST::PhiAlgebra.evaluate(subtree).round(6)]
        end.to_h

        trs_apl = per_symbol.values.sum.round(6)
        delta   = (kernel.evaluate - trs_apl).abs.round(6)

        result = { per_symbol: per_symbol, trs: trs_apl, delta: delta, match: delta < 0.0001 }
        Kernel::WORM.seal('stage:apl_verify', result)
        result
      end
    end
  end
end
