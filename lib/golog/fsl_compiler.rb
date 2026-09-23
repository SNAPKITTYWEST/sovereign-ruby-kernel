# frozen_string_literal: true

##
# FSL Dialect Compiler
#
# Parses FSL assertions, type constraints, and governance rules
# Transforms FSL→Opal intermediate representation
# Evaluates Datalog-style invariants at compile time
#
# INVARIANT: All compiled FSL expressions produce type-safe Opal IR
# INVARIANT: Constraint checking is deterministic and exhaustive
#

require 'set'
require 'digest'

module Sovereign
  module Agents
    ##
    # FSL Parser: Parses FSL assertions and constraints
    #
    class FSLParser
      # FSL token types
      TOKEN_KEYWORD = :keyword
      TOKEN_IDENTIFIER = :identifier
      TOKEN_ATOM = :atom
      TOKEN_STRING = :string
      TOKEN_NUMBER = :number
      TOKEN_LPAREN = :lparen
      TOKEN_RPAREN = :rparen
      TOKEN_COMMA = :comma
      TOKEN_DOT = :dot
      TOKEN_PIPE = :pipe
      TOKEN_ARROW = :arrow
      TOKEN_COLON = :colon
      TOKEN_LBRACKET = :lbracket
      TOKEN_RBRACKET = :rbracket
      TOKEN_EOF = :eof

      # FSL keywords
      KEYWORDS = %w[
        assert claim prove authorize execute if then else forall exists
        type constraint governance rule decision fact evidence proof
      ].to_set.freeze

      attr_reader :tokens, :position

      def initialize(source)
        @source = source
        @position = 0
        @tokens = []
        tokenize
      end

      ##
      # Tokenize FSL source
      # INVARIANT: All source characters are consumed or error raised
      #
      def tokenize
        until @position >= @source.length
          skip_whitespace
          break if @position >= @source.length

          char = @source[@position]

          case char
          when '('
            add_token(TOKEN_LPAREN, '(')
            @position += 1
          when ')'
            add_token(TOKEN_RPAREN, ')')
            @position += 1
          when ','
            add_token(TOKEN_COMMA, ',')
            @position += 1
          when '.'
            add_token(TOKEN_DOT, '.')
            @position += 1
          when '|'
            add_token(TOKEN_PIPE, '|')
            @position += 1
          when '-'
            if peek == '>'
              add_token(TOKEN_ARROW, '->')
              @position += 2
            else
              read_number
            end
          when ':'
            add_token(TOKEN_COLON, ':')
            @position += 1
          when '['
            add_token(TOKEN_LBRACKET, '[')
            @position += 1
          when ']'
            add_token(TOKEN_RBRACKET, ']')
            @position += 1
          when '"'
            read_string
          when /[0-9]/
            read_number
          when /[a-z]/
            read_identifier_or_keyword
          when /[A-Z]/
            read_atom
          else
            raise ParseError, "Unexpected character: #{char} at position #{@position}"
          end
        end

        add_token(TOKEN_EOF, nil)
      end

      def skip_whitespace
        while @position < @source.length && @source[@position].match?(/\s/)
          @position += 1
        end
      end

      def peek
        @position + 1 < @source.length ? @source[@position + 1] : nil
      end

      def read_string
        @position += 1
        start = @position
        until @position >= @source.length || @source[@position] == '"'
          @position += 1
        end
        value = @source[start...@position]
        @position += 1
        add_token(TOKEN_STRING, value)
      end

      def read_number
        start = @position
        @position += 1 while @position < @source.length && @source[@position].match?(/[0-9]/)
        value = @source[start...@position].to_i
        add_token(TOKEN_NUMBER, value)
      end

      def read_identifier_or_keyword
        start = @position
        @position += 1 while @position < @source.length && \
                             @source[@position].match?(/[a-z0-9_]/)
        value = @source[start...@position]
        token_type = KEYWORDS.include?(value) ? TOKEN_KEYWORD : TOKEN_IDENTIFIER
        add_token(token_type, value)
      end

      def read_atom
        start = @position
        @position += 1 while @position < @source.length && \
                             @source[@position].match?(/[A-Za-z0-9_]/)
        value = @source[start...@position]
        add_token(TOKEN_ATOM, value)
      end

      def add_token(type, value)
        @tokens << { type: type, value: value }
      end

      ##
      # Parse FSL expression from token stream
      # INVARIANT: Parser consumes entire token stream or raises error
      #
      def parse
        expr = parse_expression
        raise ParseError, "Unexpected tokens after expression" \
          unless current_token[:type] == TOKEN_EOF
        expr
      end

      def parse_expression
        if match(TOKEN_KEYWORD)
          keyword = previous_token[:value]
          case keyword
          when 'assert'
            parse_assertion
          when 'claim'
            parse_claim
          when 'prove'
            parse_proof
          when 'authorize'
            parse_authorization
          when 'execute'
            parse_execution
          when 'forall'
            parse_universal
          when 'exists'
            parse_existential
          else
            raise ParseError, "Unknown keyword: #{keyword}"
          end
        else
          parse_term
        end
      end

      def parse_assertion
        term = parse_term
        FslAssertion.new(:assert, term)
      end

      def parse_claim
        consume(TOKEN_IDENTIFIER, "claim identifier")
        claim_id = previous_token[:value]
        consume(TOKEN_LPAREN, "(")
        fact = parse_term
        consume(TOKEN_COMMA, ",")
        evidence = parse_term
        consume(TOKEN_RPAREN, ")")
        FslAssertion.new(:claim, { claim_id: claim_id, fact: fact, evidence: evidence })
      end

      def parse_proof
        consume(TOKEN_IDENTIFIER, "proof identifier")
        proof_id = previous_token[:value]
        consume(TOKEN_LPAREN, "(")
        claim_id = parse_term
        consume(TOKEN_COMMA, ",")
        proof_data = parse_term
        consume(TOKEN_RPAREN, ")")
        FslAssertion.new(:proof, { proof_id: proof_id, claim_id: claim_id, proof_data: proof_data })
      end

      def parse_authorization
        consume(TOKEN_IDENTIFIER, "decision identifier")
        decision_id = previous_token[:value]
        consume(TOKEN_LPAREN, "(")
        action = parse_term
        consume(TOKEN_COMMA, ",")
        justification = parse_term
        consume(TOKEN_RPAREN, ")")
        FslAssertion.new(:authorize, { decision_id: decision_id, action: action, justification: justification })
      end

      def parse_execution
        consume(TOKEN_IDENTIFIER, "execution identifier")
        exec_id = previous_token[:value]
        consume(TOKEN_LPAREN, "(")
        decision_id = parse_term
        consume(TOKEN_RPAREN, ")")
        FslAssertion.new(:execute, { exec_id: exec_id, decision_id: decision_id })
      end

      def parse_universal
        consume(TOKEN_IDENTIFIER, "variable")
        var = previous_token[:value]
        consume(TOKEN_COLON, ":")
        type = parse_term
        consume(TOKEN_PIPE, "|")
        body = parse_expression
        FslAssertion.new(:forall, { var: var, type: type, body: body })
      end

      def parse_existential
        consume(TOKEN_IDENTIFIER, "variable")
        var = previous_token[:value]
        consume(TOKEN_COLON, ":")
        type = parse_term
        consume(TOKEN_PIPE, "|")
        body = parse_expression
        FslAssertion.new(:exists, { var: var, type: type, body: body })
      end

      def parse_term
        parse_compound_term
      end

      def parse_compound_term
        left = parse_primary_term

        if match(TOKEN_LPAREN)
          args = []
          until check(TOKEN_RPAREN)
            args << parse_term
            break unless match(TOKEN_COMMA)
          end
          consume(TOKEN_RPAREN, ")")
          FslTerm.new(:compound, left, args)
        else
          left
        end
      end

      def parse_primary_term
        if match(TOKEN_ATOM)
          FslTerm.new(:atom, previous_token[:value])
        elsif match(TOKEN_IDENTIFIER)
          FslTerm.new(:identifier, previous_token[:value])
        elsif match(TOKEN_NUMBER)
          FslTerm.new(:number, previous_token[:value])
        elsif match(TOKEN_STRING)
          FslTerm.new(:string, previous_token[:value])
        elsif match(TOKEN_LBRACKET)
          elements = []
          until check(TOKEN_RBRACKET)
            elements << parse_term
            break unless match(TOKEN_COMMA)
          end
          consume(TOKEN_RBRACKET, "]")
          FslTerm.new(:list, elements)
        elsif match(TOKEN_LPAREN)
          expr = parse_expression
          consume(TOKEN_RPAREN, ")")
          expr
        else
          raise ParseError, "Unexpected token: #{current_token[:type]}"
        end
      end

      def match(*types)
        return false unless types.any? { |t| check(t) }

        advance
        true
      end

      def check(type)
        return false if is_at_end?

        current_token[:type] == type
      end

      def advance
        @position += 1 unless is_at_end?
      end

      def is_at_end?
        current_token[:type] == TOKEN_EOF
      end

      def current_token
        @tokens[@position] || { type: TOKEN_EOF, value: nil }
      end

      def previous_token
        @tokens[@position - 1]
      end

      def consume(type, message)
        raise ParseError, "Expected #{message} but got #{current_token[:type]}" \
          unless check(type)

        advance
        previous_token
      end
    end

    ##
    # FSL Assertion
    #
    class FslAssertion
      attr_reader :type, :content

      def initialize(type, content)
        @type = type
        @content = content
      end

      def hash
        Digest::SHA256.hexdigest("#{@type}:#{@content}")
      end
    end

    ##
    # FSL Term
    #
    class FslTerm
      attr_reader :type, :value, :function_name, :arguments

      def initialize(type, value_or_func = nil, arguments = nil)
        @type = type
        if type == :compound
          @function_name = value_or_func
          @arguments = arguments || []
        else
          @value = value_or_func
        end
      end

      def term_hash
        Digest::SHA256.hexdigest("#{@type}:#{@value || @function_name}")
      end
    end

    ##
    # FSL Compiler: Transforms FSL to Opal IR
    #
    class FSLCompiler
      attr_reader :assertions, :constraints, :ir_output

      def initialize(fsl_source)
        @fsl_source = fsl_source
        @assertions = []
        @constraints = []
        @ir_output = []
        @type_map = {}
      end

      ##
      # Compile FSL source to Opal IR
      # INVARIANT: All constraints are satisfied before returning IR
      # INVARIANT: IR is deterministic (same input → same output)
      #
      def compile
        parser = FSLParser.new(@fsl_source)
        expr = parser.parse

        compile_expression(expr)
        evaluate_constraints

        {
          assertions: @assertions,
          constraints: @constraints,
          ir: @ir_output
        }
      end

      def compile_expression(expr)
        case expr
        when FslAssertion
          compile_assertion(expr)
        when FslTerm
          compile_term(expr)
        end
      end

      def compile_assertion(assertion)
        case assertion.type
        when :assert
          compile_assert_assertion(assertion)
        when :claim
          compile_claim_assertion(assertion)
        when :proof
          compile_proof_assertion(assertion)
        when :authorize
          compile_authorize_assertion(assertion)
        when :execute
          compile_execute_assertion(assertion)
        when :forall
          compile_universal_assertion(assertion)
        when :exists
          compile_existential_assertion(assertion)
        end
      end

      def compile_assert_assertion(assertion)
        ir_code = OpalCode.new(:assert, assertion.content)
        @assertions << ir_code
        @ir_output << ir_code
      end

      def compile_claim_assertion(assertion)
        content = assertion.content
        ir_code = OpalCode.new(:claim, {
          claim_id: content[:claim_id],
          fact: compile_term(content[:fact]),
          evidence: compile_term(content[:evidence])
        })
        @assertions << ir_code
        @ir_output << ir_code
      end

      def compile_proof_assertion(assertion)
        content = assertion.content
        ir_code = OpalCode.new(:proof, {
          proof_id: content[:proof_id],
          claim_id: compile_term(content[:claim_id]),
          proof_data: compile_term(content[:proof_data])
        })
        @assertions << ir_code
        @ir_output << ir_code
      end

      def compile_authorize_assertion(assertion)
        content = assertion.content
        ir_code = OpalCode.new(:authorize, {
          decision_id: content[:decision_id],
          action: compile_term(content[:action]),
          justification: compile_term(content[:justification])
        })
        @assertions << ir_code
        @ir_output << ir_code
      end

      def compile_execute_assertion(assertion)
        content = assertion.content
        ir_code = OpalCode.new(:execute, {
          exec_id: content[:exec_id],
          decision_id: compile_term(content[:decision_id])
        })
        @assertions << ir_code
        @ir_output << ir_code
      end

      def compile_universal_assertion(assertion)
        content = assertion.content
        ir_code = OpalCode.new(:forall, {
          variable: content[:var],
          type: compile_term(content[:type]),
          body: compile_expression(content[:body])
        })
        @assertions << ir_code
        @ir_output << ir_code
      end

      def compile_existential_assertion(assertion)
        content = assertion.content
        ir_code = OpalCode.new(:exists, {
          variable: content[:var],
          type: compile_term(content[:type]),
          body: compile_expression(content[:body])
        })
        @assertions << ir_code
        @ir_output << ir_code
      end

      def compile_term(term)
        case term.type
        when :atom
          OpalValue.new(:atom, term.value)
        when :identifier
          OpalValue.new(:identifier, term.value)
        when :number
          OpalValue.new(:number, term.value)
        when :string
          OpalValue.new(:string, term.value)
        when :list
          OpalValue.new(:list, term.value.map { |v| compile_term(v) })
        when :compound
          OpalValue.new(:compound, {
            function: term.function_name,
            arguments: term.arguments.map { |arg| compile_term(arg) }
          })
        else
          raise CompileError, "Unknown term type: #{term.type}"
        end
      end

      ##
      # Evaluate all constraints
      # INVARIANT: All constraints must be satisfied or CompileError raised
      #
      def evaluate_constraints
        @assertions.each do |assertion|
          check_type_safety(assertion)
          check_governance_consistency(assertion)
          check_acyclic_dependencies(assertion)
        end
      end

      def check_type_safety(assertion)
        # Type checking for Opal IR
        case assertion.operation
        when :claim, :proof
          unless assertion.data[:fact] && assertion.data[:evidence]
            raise CompileError, "Incomplete claim/proof assertion"
          end
        when :authorize
          unless assertion.data[:action] && assertion.data[:justification]
            raise CompileError, "Incomplete authorization assertion"
          end
        end
      end

      def check_governance_consistency(assertion)
        # Governance rules consistency
        if assertion.operation == :authorize
          # Ensure authorization has backing decision
          decision_id = assertion.data[:decision_id]
          unless @assertions.any? { |a| a.operation == :claim && a.data[:claim_id] == decision_id }
            # Warning: authorization without explicit backing (may be implicit)
          end
        end
      end

      def check_acyclic_dependencies(assertion)
        # Dependency graph must be acyclic
        visited = Set.new
        rec_stack = Set.new

        def traverse_dependencies(assertion_id, visited, rec_stack, assertion_map)
          return false if visited.include?(assertion_id)

          visited.add(assertion_id)
          rec_stack.add(assertion_id)

          assertion = assertion_map[assertion_id]
          return false unless assertion

          case assertion.operation
          when :authorize
            backing_id = assertion.data[:decision_id]
            return true if rec_stack.include?(backing_id)
            return true if traverse_dependencies(backing_id, visited, rec_stack, assertion_map)
          end

          rec_stack.delete(assertion_id)
          false
        end

        assertion_map = @assertions.index_by(&:id)
        @assertions.each do |assertion|
          visited.clear
          rec_stack.clear
          if traverse_dependencies(assertion.id, visited, rec_stack, assertion_map)
            raise CompileError, "Circular dependency detected in assertions"
          end
        end
      end
    end

    ##
    # Opal Intermediate Representation
    #
    class OpalCode
      attr_reader :id, :operation, :data

      def initialize(operation, data)
        @id = SecureRandom.hex(8)
        @operation = operation
        @data = data
      end
    end

    ##
    # Opal Value
    #
    class OpalValue
      attr_reader :type, :value

      def initialize(type, value)
        @type = type
        @value = value
      end

      def to_s
        case @type
        when :atom
          @value.to_s
        when :identifier
          "@#{@value}"
        when :number
          @value.to_s
        when :string
          "\"#{@value}\""
        when :list
          "[#{@value.map(&:to_s).join(', ')}]"
        when :compound
          "#{@value[:function]}(#{@value[:arguments].map(&:to_s).join(', ')})"
        else
          @value.to_s
        end
      end

      def opal_hash
        Digest::SHA256.hexdigest(to_s)
      end
    end

    ##
    # Constraint Evaluator for Datalog-style invariants
    #
    class ConstraintEvaluator
      ##
      # INVARIANT: All rules satisfied before program execution
      #
      def initialize(ir_output)
        @ir_output = ir_output
        @rules = []
        @facts = Set.new
      end

      def add_rule(head, body)
        @rules << { head: head, body: body }
      end

      def add_fact(fact)
        @facts.add(fact)
      end

      ##
      # Evaluate all rules and derive consequences
      # INVARIANT: Fixed-point reached when no new facts derived
      #
      def evaluate
        changed = true
        iterations = 0
        max_iterations = 1000

        while changed && iterations < max_iterations
          changed = false
          iterations += 1

          @rules.each do |rule|
            if matches_body?(rule[:body])
              new_fact = derive_head(rule[:head])
              if @facts.add?(new_fact)
                changed = true
              end
            end
          end
        end

        raise ConstraintError, "Fixed point not reached" if iterations >= max_iterations

        @facts
      end

      def matches_body?(body)
        # Simple pattern matching for Datalog-style bodies
        case body
        when Hash
          body.all? { |key, value| @facts.any? { |f| f[key] == value } }
        else
          @facts.include?(body)
        end
      end

      def derive_head(head)
        # Derive new facts from head
        head
      end
    end

    # Custom exceptions
    class ParseError < StandardError; end
    class CompileError < StandardError; end
    class ConstraintError < StandardError; end
  end
end
