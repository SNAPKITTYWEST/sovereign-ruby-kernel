# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# Copyright (C) 2026 SNAPKITTYWEST / Sovereign Kernel Project
# CLONE_GATE: sovereign-ruby-kernel::stages::clojure_trs
# frozen_string_literal: true

require 'open3'
require_relative '../kernel/worm'
require_relative '../kernel/symbolic_kernel'

module Sovereign
  module Stages
    module ClojureTRS
      def self.run(kernel, clj_dir: nil)
        if clj_dir && File.directory?(clj_dir)
          out, _err, status = Open3.capture3('clojure', '-M', '-m', 'sovereign.core', chdir: clj_dir)
          if status.success?
            trs_match  = out.match(/TRS num\s+=\s+([\d.]+)/)
            norm_match = out.match(/Norm N\(TRS\)\s+=\s+([-\d.]+)/)
            result = { trs: trs_match&.[](1)&.to_f, norm: norm_match&.[](1)&.to_f, source: :clojure }
            Kernel::WORM.seal('stage:clojure', result)
            return result
          end
        end

        trs  = kernel.evaluate
        conj = kernel.evaluate_conjugate
        norm = kernel.norm
        result = { trs: trs.round(6), conjugate: conj.round(6), norm: norm.round(6), source: :inline }
        Kernel::WORM.seal('stage:clojure', result)
        result
      end
    end
  end
end
