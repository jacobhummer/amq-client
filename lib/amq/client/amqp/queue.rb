# encoding: utf-8

require "amq/client/entity"

module AMQ
  module Client
    class Queue < Entity
      def initialize(client, name, default_channel)
        @name, @default_channel = name, default_channel
        super(client)
      end

      def declare(channel = @default_channel, passive = false, durable = false, exclusive = false, auto_delete = false, arguments = nil, &block)
        data = Protocol::Queue::Declare.encode(channel, @name, passive, durable, exclusive, auto_delete, arguments)
        p data #####
        @client.send(data)
        self.callbacks[:declare] = block
        self
      end

      def bind(exchange, channel = @default_channel, &block)
        data = Protocol::Queue::Bind.encode(channel, @name, exchange, routing_key, arguments)
        @client.send(data)
        self.callbacks[:bind] = block
        self
      end

      # Basic.Consume
      def consume(&block)
        if @consumer_tag
          raise RuntimeError.new("This instance is already being consumed! Create another one using #dup.")
        end
        @consumer_tag = "random sh1t3"
        client.consumers[@consumer_tag] = self ### WHAT IF there'll be more consume blocks for the same object? Now that's about opinion, but we are NOT building an opinionated API here!!!!
        self.callbacks[:consume] = block
      end

      def dup
        if @name.eql?("")
          raise RuntimeError.new("You can't clone anonymous queue until it receives back the name in Queue.Declare-Ok response. Move the code with #dup to the callback for the #declare method.") # TODO: that's not true in all cases, imagine the user didn't call #declare yet.
        end
        instance = self.dup
        instance.instance_variable_set(:@consumer_tag, nil)
        instance
      end

      # === Handlers ===
      # Get the first queue which didn't receive Queue.Declare-Ok yet and run its declare callback. The cache includes only queues with {nowait: false}.
      self.handle(Protocol::Queue::DeclareOk) do |client, method|
        queue = client.cache[AMQ::Protocol::Queue::DeclareOk].shift
        queue.exec_callback(:declare, frame.queue_name, frame.consumer_count, frame.messages_count)
      end

      self.handle(Protocol::Queue::BindOk) do |client, method|
      end

      # Basic.Deliver
      self.handle(Protocol::Basic::Deliver) do |client, method, header, *body|
        queue = client.consumers[method.consumer_tag]
        body  = body.reduce("") { |buffer, frame| buffer += frame.body }
        queue.exec_callback(:consume, body)
      end
    end
  end
end