#!/usr/bin/env ruby
# frozen_string_literal: true

require "dotenv"
require "raix"

# Load environment variables from .env file
Dotenv.load

# Configure Raix with API keys
Raix.configure do |config|
  config.openrouter_api_key = ENV.fetch("OR_ACCESS_TOKEN", nil)
  config.openai_api_key = ENV.fetch("OAI_ACCESS_TOKEN", nil)
end

module Examples
  # Demonstrates advanced tool/function control features:
  # - Multiple tool calls in one response
  # - max_tool_calls limiting
  # - stop_tool_calls_and_respond! for early termination
  class AdvancedToolControl
    include Raix::ChatCompletion
    include Raix::FunctionDispatch

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "gpt-4o-mini")
      config.temperature = 0.7
      config.max_tool_calls = 10 # Default limit
    end

    attr_reader :call_log

    def initialize
      @call_log = []
    end

    # Tool 1: Search database
    function :search_database,
             "Search the database for information",
             query: { type: "string", required: true },
             limit: { type: "integer", default: 10 } do |args|
      log_call(:search_database, args)
      "Found #{rand(3..8)} results for '#{args[:query]}'"
    end

    # Tool 2: Calculate statistics
    function :calculate_stats,
             "Calculate statistics on data",
             dataset: { type: "string", required: true },
             metric: { type: "string", required: true } do |args|
      log_call(:calculate_stats, args)
      "#{args[:metric].capitalize}: #{rand(10..100)}"
    end

    # Tool 3: Send notification
    function :send_notification,
             "Send a notification to user",
             message: { type: "string", required: true },
             priority: { type: "string", enum: %w[low medium high] } do |args|
      log_call(:send_notification, args)
      "Notification sent: #{args[:message]} (priority: #{args[:priority]})"
    end

    # Tool 4: Check status
    function :check_status,
             "Check the status of a system",
             system: { type: "string", required: true } do |args|
      log_call(:check_status, args)
      "System '#{args[:system]}' is operational"
    end

    # Tool 5: Complete task
    function :complete_task,
             "Mark task as complete and stop further processing",
             task_id: { type: "string", required: true },
             summary: { type: "string", required: true } do |args|
      log_call(:complete_task, args)

      # Signal to stop tool calls and provide final response
      stop_tool_calls_and_respond!

      "Task #{args[:task_id]} completed: #{args[:summary]}"
    end

    def log_call(function_name, args)
      @call_log << { function: function_name, args:, timestamp: Time.now }
      puts "   🔧 Called: #{function_name}(#{args.inspect})"
    end

    def print_call_log
      puts "\n📋 Tool Call Log:"
      puts "-" * 60
      call_log.each_with_index do |entry, i|
        puts "#{i + 1}. #{entry[:function]} - #{entry[:timestamp].strftime('%H:%M:%S.%L')}"
        puts "   Args: #{entry[:args]}"
      end
      puts
    end

    # Example 1: Multiple tool calls in one response
    def demo_multiple_calls
      puts "Demo 1: Multiple Tool Calls"
      puts "=" * 60
      puts "Task: Analyze sales data and notify team"
      puts

      transcript << {
        user: "Search for Q4 sales data, calculate the average revenue, "\
              "check the analytics system status, and send a high-priority "\
              "notification with the results."
      }

      result = chat_completion
      print_call_log

      puts "✅ Final Response:"
      puts result
      puts
    end

    # Example 2: Limited tool calls
    def demo_limited_calls
      puts "Demo 2: Limited Tool Calls"
      puts "=" * 60
      puts "Max tool calls: 3"
      puts

      transcript << {
        user: "I need you to search for customer data, calculate conversion rates, "\
              "check system status, search for product data, calculate product stats, "\
              "and send notifications to the team."
      }

      result = chat_completion(max_tool_calls: 3)
      print_call_log

      puts "✅ Final Response:"
      puts result
      puts
      puts "Note: AI was forced to respond after 3 tool calls"
      puts
    end

    # Example 3: Early termination with stop_tool_calls_and_respond!
    def demo_early_termination
      puts "Demo 3: Early Termination"
      puts "=" * 60
      puts "Using complete_task() to stop tool execution"
      puts

      transcript << {
        user: "Search the database for order #12345, check its status, "\
              "verify payment, and then complete the task with ID 'ORDER-CHECK' "\
              "once you have the information."
      }

      result = chat_completion
      print_call_log

      puts "✅ Final Response:"
      puts result
      puts
      puts "Note: complete_task() called stop_tool_calls_and_respond!"
      puts
    end

    def self.run!
      puts "🎯 Raix Advanced Tool Control Demo"
      puts "Multiple calls, limiting, and early termination"
      puts "=" * 60
      puts

      # Demo 1: Multiple calls
      demo1 = new
      demo1.demo_multiple_calls

      puts "\n" + "=" * 60 + "\n\n"

      # Demo 2: Limited calls
      demo2 = new
      demo2.demo_limited_calls

      puts "\n" + "=" * 60 + "\n\n"

      # Demo 3: Early termination
      demo3 = new
      demo3.demo_early_termination

      puts "=" * 60
      puts "✨ Tool control demo complete!"
      puts
      puts "💡 Key Features Demonstrated:"
      puts "   • Multiple tool calls: AI can call several functions in one turn"
      puts "   • max_tool_calls: Limit function execution to prevent runaway loops"
      puts "   • stop_tool_calls_and_respond!: Exit tool loop early from within a function"
      puts
      puts "🎯 Use Cases:"
      puts "   • Task automation with multiple steps"
      puts "   • Autonomous agents with safeguards"
      puts "   • Complex workflows requiring orchestration"
      puts "   • Order processing with multiple validations"
    end
  end

  # Example showing a more realistic autonomous agent scenario
  class OrderProcessingAgent
    include Raix::ChatCompletion
    include Raix::FunctionDispatch

    configure do |config|
      config.model = ENV.fetch("RAIX_EXAMPLE_MODEL", "gpt-4o-mini")
      config.temperature = 0.3
      config.max_tool_calls = 8 # Reasonable limit for order processing
    end

    attr_accessor :order_status

    def initialize
      @order_status = {
        validated: false,
        payment_verified: false,
        inventory_checked: false,
        shipping_calculated: false,
        processed: false
      }
    end

    function :validate_order,
             "Validate order details and customer information",
             order_id: { type: "string", required: true } do |args|
      puts "   ✓ Validating order #{args[:order_id]}..."
      @order_status[:validated] = true
      "Order #{args[:order_id]} validated successfully"
    end

    function :verify_payment,
             "Verify payment method and process payment",
             order_id: { type: "string", required: true },
             amount: { type: "number", required: true } do |args|
      puts "   ✓ Verifying payment of $#{args[:amount]}..."
      @order_status[:payment_verified] = true
      "Payment of $#{args[:amount]} verified and authorized"
    end

    function :check_inventory,
             "Check if items are in stock",
             items: { type: "array", required: true } do |args|
      puts "   ✓ Checking inventory for #{args[:items].length} items..."
      @order_status[:inventory_checked] = true
      "All items in stock and reserved"
    end

    function :calculate_shipping,
             "Calculate shipping cost and estimated delivery",
             zip_code: { type: "string", required: true } do |args|
      puts "   ✓ Calculating shipping to #{args[:zip_code]}..."
      @order_status[:shipping_calculated] = true
      "Shipping: $12.50, Estimated delivery: 3-5 business days"
    end

    function :process_order,
             "Finalize order processing",
             order_id: { type: "string", required: true } do |args|
      if order_status.values.take(4).all?
        puts "   ✓ All validations passed, processing order..."
        @order_status[:processed] = true
        stop_tool_calls_and_respond!
        "Order #{args[:order_id]} processed successfully. Confirmation email sent."
      else
        "Cannot process: Missing validations #{order_status.select { |k, v| !v }.keys}"
      end
    end

    def process_customer_order(order_details)
      puts "📦 Processing Order: #{order_details[:order_id]}"
      puts "=" * 60
      puts

      transcript << {
        system: "You are an order processing agent. Validate, verify payment, "\
                "check inventory, calculate shipping, then process the order."
      }
      transcript << {
        user: "Process this order: #{order_details.inspect}"
      }

      result = chat_completion

      puts "\n📊 Order Status:"
      order_status.each { |k, v| puts "   #{k}: #{v ? '✓' : '✗'}" }
      puts
      puts "✅ Result: #{result}"
      puts
    end

    def self.run!
      puts "\n\n" + "=" * 60
      puts "🤖 Autonomous Order Processing Agent"
      puts "=" * 60
      puts

      agent = new
      agent.process_customer_order(
        order_id: "ORD-2024-001",
        customer: "John Doe",
        items: %w[PROD-123 PROD-456],
        total: 149.99,
        zip_code: "94105"
      )

      puts "💡 Agent Features:"
      puts "   • Autonomous decision making"
      puts "   • Multiple validation steps"
      puts "   • Automatic termination when complete"
      puts "   • Safety limits with max_tool_calls"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Examples::AdvancedToolControl.run!
  Examples::OrderProcessingAgent.run!
end
