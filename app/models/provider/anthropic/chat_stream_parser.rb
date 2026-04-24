class Provider::Anthropic::ChatStreamParser
  ChatResponse = Provider::LlmConcept::ChatResponse
  ChatMessage = Provider::LlmConcept::ChatMessage
  ChatStreamChunk = Provider::LlmConcept::ChatStreamChunk
  ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

  def initialize
    @blocks = []
    @message_id = nil
    @model = nil
  end

  def push(event)
    case field(event, :type).to_s
    when "message_start"
      msg = field(event, :message)
      @message_id = field(msg, :id) if msg
      @model = field(msg, :model) if msg
      []
    when "content_block_start"
      index = field(event, :index)
      @blocks[index] = init_block(field(event, :content_block))
      []
    when "content_block_delta"
      index = field(event, :index)
      apply_delta(index, field(event, :delta))
    when "content_block_stop"
      finalize_block(field(event, :index))
      []
    else
      []
    end
  end

  def finalize
    text = blocks_of(:text).map { |b| b[:text] }.join
    function_requests = blocks_of(:tool_use).map do |b|
      # Tools with no inputs produce no input_json_delta events, leaving input_json empty.
      # Default to "{}" so downstream JSON.parse doesn't choke.
      args = b[:input_json].to_s
      args = "{}" if args.empty?
      ChatFunctionRequest.new(
        id: b[:id],
        call_id: b[:id],
        function_name: b[:name],
        function_args: args
      )
    end

    messages = text.present? ? [ ChatMessage.new(id: @message_id, output_text: text) ] : []

    response = ChatResponse.new(
      id: @message_id,
      model: @model,
      messages: messages,
      function_requests: function_requests
    )

    ChatStreamChunk.new(type: "response", data: response)
  end

  private
    def init_block(content_block)
      type = field(content_block, :type).to_s
      case type
      when "text"
        { type: :text, text: "" }
      when "tool_use"
        {
          type: :tool_use,
          id: field(content_block, :id),
          name: field(content_block, :name),
          input_json: ""
        }
      else
        { type: type.to_sym }
      end
    end

    def apply_delta(index, delta)
      block = @blocks[index]
      return [] if block.nil? || delta.nil?

      case field(delta, :type).to_s
      when "text_delta"
        text = field(delta, :text).to_s
        block[:text] = block[:text].to_s + text
        [ ChatStreamChunk.new(type: "output_text", data: text) ]
      when "input_json_delta"
        partial = field(delta, :partial_json).to_s
        block[:input_json] = block[:input_json].to_s + partial
        []
      else
        []
      end
    end

    def finalize_block(index)
      # nothing to do — tool_use input_json is already accumulated
    end

    def blocks_of(type)
      @blocks.compact.select { |b| b[:type] == type }
    end

    def field(obj, key)
      return nil if obj.nil?
      if obj.respond_to?(key)
        obj.public_send(key)
      elsif obj.respond_to?(:[])
        obj[key] || obj[key.to_s]
      end
    end
end
