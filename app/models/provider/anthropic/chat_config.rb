class Provider::Anthropic::ChatConfig
  def initialize(prompt:, chat: nil, functions: [], function_results: [])
    @prompt = prompt
    @chat = chat
    @functions = functions
    @function_results = function_results
  end

  def tools
    functions.map do |fn|
      {
        name: fn[:name],
        description: fn[:description],
        input_schema: fn[:params_schema]
      }
    end
  end

  def messages
    history = build_history

    if function_results.any?
      # If the current in-flight assistant message isn't persisted yet
      # (Claude called a tool as its first response, before any text),
      # synthesize its tool_use turn from the function_results data so
      # Anthropic sees a matching tool_use for every tool_result.
      last = history.last
      needs_synth = last.nil? || last[:role] != "assistant" ||
                    !Array(last[:content]).any? { |b| b.is_a?(Hash) && b[:type] == "tool_use" }

      if needs_synth
        history << {
          role: "assistant",
          content: function_results.map do |r|
            {
              type: "tool_use",
              id: r[:call_id],
              name: r[:function_name],
              input: JSON.parse(r[:function_arguments].presence || "{}")
            }
          end
        }
      end

      history << {
        role: "user",
        content: function_results.map do |r|
          {
            type: "tool_result",
            tool_use_id: r[:call_id],
            content: r[:output].to_json
          }
        end
      }
    elsif history.empty? || history.last[:role] != "user"
      history << { role: "user", content: prompt }
    end

    history
  end

  private
    attr_reader :prompt, :chat, :functions, :function_results

    def build_history
      return [] if chat.nil?

      chat.messages.ordered.each_with_object([]) do |msg, acc|
        case msg
        when UserMessage
          acc << { role: "user", content: user_content(msg) }
        when AssistantMessage
          next if msg.content.blank? && msg.tool_calls.empty?

          fn_calls = msg.tool_calls.select { |tc| tc.is_a?(ToolCall::Function) }

          # Anthropic requires:
          #   assistant: [tool_use, ...]
          #   user: [tool_result, ...]
          #   assistant: [final text]
          # — text + tool_use can't share an assistant message without breaking the pairing.
          if fn_calls.any?
            acc << {
              role: "assistant",
              content: fn_calls.map do |tc|
                {
                  type: "tool_use",
                  id: tc.provider_id,
                  name: tc.function_name,
                  input: JSON.parse(tc.function_arguments.presence || "{}")
                }
              end
            }
            acc << {
              role: "user",
              content: fn_calls.map do |tc|
                {
                  type: "tool_result",
                  tool_use_id: tc.provider_id,
                  content: tc.function_result.to_json
                }
              end
            }
          end

          if msg.content.present?
            acc << { role: "assistant", content: [ { type: "text", text: msg.content } ] }
          end
        end
      end
    end

    # Build a user-message content array that includes any attached
    # images/PDFs as Claude vision/document blocks, plus the text.
    # Returns a plain string when there are no attachments (keeps the
    # simple case readable).
    def user_content(msg)
      return msg.content unless msg.respond_to?(:attachments) && msg.attachments.attached?

      blocks = msg.attachments.map { |a| attachment_block(a) }.compact
      blocks << { type: "text", text: msg.content } if msg.content.present?
      blocks.presence || msg.content
    end

    def attachment_block(att)
      data = Base64.strict_encode64(att.download)
      if att.content_type == "application/pdf"
        {
          type: "document",
          source: { type: "base64", media_type: "application/pdf", data: data }
        }
      elsif att.content_type&.start_with?("image/")
        {
          type: "image",
          source: { type: "base64", media_type: att.content_type, data: data }
        }
      end
    end
end
