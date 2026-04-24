class Message < ApplicationRecord
  ATTACHMENT_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp application/pdf].freeze
  ATTACHMENT_MAX_SIZE = 20.megabytes
  ATTACHMENT_MAX_COUNT = 5

  belongs_to :chat
  has_many :tool_calls, dependent: :destroy
  has_many_attached :attachments

  enum :status, {
    pending: "pending",
    complete: "complete",
    failed: "failed"
  }

  validates :content, presence: true, unless: -> { attachments.any? }
  validate :attachments_within_limits

  after_create_commit -> { broadcast_append_to chat, target: "messages" }, if: :broadcast?
  after_update_commit -> { broadcast_update_to chat }, if: :broadcast?

  scope :ordered, -> { order(created_at: :asc) }

  private
    def broadcast?
      true
    end

    def attachments_within_limits
      return unless attachments.attached?

      if attachments.count > ATTACHMENT_MAX_COUNT
        errors.add(:attachments, "can't exceed #{ATTACHMENT_MAX_COUNT} files")
      end

      attachments.each do |a|
        if a.byte_size > ATTACHMENT_MAX_SIZE
          errors.add(:attachments, "#{a.filename}: exceeds #{ATTACHMENT_MAX_SIZE / 1.megabyte}MB limit")
        end
        unless ATTACHMENT_CONTENT_TYPES.include?(a.content_type)
          errors.add(:attachments, "#{a.filename}: unsupported type (#{a.content_type})")
        end
      end
    end
end
