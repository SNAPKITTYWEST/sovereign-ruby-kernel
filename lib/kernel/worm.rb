# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::kernel::worm
# frozen_string_literal: true

require 'json'
require 'digest'

module Sovereign
  module Kernel
    module WORM
      @chain = []
      @mutex = Mutex.new

      def self.seal(label, payload)
        @mutex.synchronize do
          prev = @chain.empty? ? '0' * 64 : @chain.last[:seal]
          ts   = Time.now.utc.iso8601
          raw  = JSON.generate({ label: label, payload: payload, ts: ts, prev: prev })
          hash = Digest::SHA256.hexdigest(raw)
          entry = { label: label, payload: payload, ts: ts, prev: prev, seal: hash }.freeze
          @chain << entry
          entry
        end
      end

      def self.chain = @chain.dup
      def self.length = @chain.length
      def self.last_seal = @chain.last&.dig(:seal)

      def self.valid?
        @chain.each_cons(2).all? { |a, b| b[:prev] == a[:seal] }
      end

      def self.verify_entry(index)
        return false if index >= @chain.length
        entry = @chain[index]
        raw = JSON.generate({
          label: entry[:label], payload: entry[:payload],
          ts: entry[:ts], prev: entry[:prev]
        })
        Digest::SHA256.hexdigest(raw) == entry[:seal]
      end

      def self.reset!
        @mutex.synchronize { @chain.clear }
      end

      def self.export
        JSON.pretty_generate(@chain)
      end
    end
  end
end
