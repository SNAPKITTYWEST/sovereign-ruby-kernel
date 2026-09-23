# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::kernel::governance
# frozen_string_literal: true

require_relative 'worm'

module Sovereign
  module Kernel
    module Governance
      STATES = %i[init verified sealed rejected].freeze

      class StateError < StandardError; end

      TRANSITIONS = {
        init:     %i[verified rejected],
        verified: %i[sealed rejected],
        sealed:   [],
        rejected: %i[init]
      }.freeze

      class Gate
        attr_reader :state, :history

        def initialize
          @state = :init
          @history = [{ state: :init, at: Time.now.utc }]
        end

        def transition!(new_state, evidence: {})
          unless TRANSITIONS[@state].include?(new_state)
            raise StateError, "#{@state} → #{new_state} forbidden"
          end
          @state = new_state
          @history << { state: new_state, at: Time.now.utc, evidence: evidence }
          WORM.seal("governance:#{new_state}", {
            from: @history[-2][:state], to: new_state, evidence: evidence
          })
          new_state
        end

        def sealed? = @state == :sealed
        def rejected? = @state == :rejected

        def require_sealed!
          raise StateError, "Expected sealed, got #{@state}" unless sealed?
        end
      end

      def self.new_gate = Gate.new
    end
  end
end
