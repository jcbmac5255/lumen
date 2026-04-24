class MessagesController < ApplicationController
  guard_feature unless: -> { Current.user.ai_enabled? }

  before_action :set_chat

  def create
    @message = UserMessage.new(
      chat: @chat,
      content: message_params[:content],
      ai_model: message_params[:ai_model]
    )
    if message_params[:attachments].present?
      @message.attachments.attach(message_params[:attachments])
    end
    @message.save!

    redirect_to chat_path(@chat, thinking: true)
  end

  private
    def set_chat
      @chat = Current.user.chats.find(params[:chat_id])
    end

    def message_params
      params.require(:message).permit(:content, :ai_model, attachments: [])
    end
end
