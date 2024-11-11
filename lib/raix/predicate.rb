# frozen_string_literal: true

module Raix
  # A module for handling yes/no questions using AI chat completion.
  # When included in a class, it provides methods to define handlers for
  # yes and no responses.
  #
  # @example
  #   class Question
  #     include Raix::Predicate
  #
  #     yes do |explanation|
  #       puts "Yes: #{explanation}"
  #     end
  #
  #     no do |explanation|
  #       puts "No: #{explanation}"
  #     end
  #   end
  #
  #   question = Question.new
  #   question.ask("Is Ruby a programming language?")
  module Predicate
    include ChatCompletion

    def self.included(base)
      base.extend(ClassMethods)
    end

    def ask(question)
      raise "Please define a yes and/or no block" if self.class.yes_block.nil? && self.class.no_block.nil?

      transcript << { system: "Always answer 'Yes, ', 'No, ', or 'Maybe, ' followed by a concise explanation!" }
      transcript << { user: question }

      chat_completion.tap do |response|
        if response.downcase.start_with?("yes,")
          instance_exec(response, &self.class.yes_block) if self.class.yes_block
        elsif response.downcase.start_with?("no,")
          instance_exec(response, &self.class.no_block) if self.class.no_block
        elsif response.downcase.start_with?("maybe,")
          instance_exec(response, &self.class.maybe_block) if self.class.maybe_block
        end
      end
    end

    # Class methods added to the including class
    module ClassMethods
      attr_reader :yes_block, :no_block, :maybe_block

      def yes?(&block)
        @yes_block = block
      end

      def no?(&block)
        @no_block = block
      end

      def maybe?(&block)
        @maybe_block = block
      end
    end
  end
end
