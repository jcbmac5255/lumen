class Bill < ApplicationRecord
  include Monetizable

  FREQUENCIES = %w[weekly biweekly monthly quarterly semi_annual annual].freeze

  belongs_to :family
  belongs_to :category, optional: true
  belongs_to :paid_from_account, class_name: "Account", optional: true
  belongs_to :paid_to_account, class_name: "Account", optional: true
  has_many :bill_payments, dependent: :destroy

  monetize :amount

  validates :name, :amount, :currency, :anchor_date, :frequency, presence: true
  validates :frequency, inclusion: { in: FREQUENCIES }
  validate :paid_to_account_must_be_liability
  validate :paid_to_and_from_accounts_must_differ
  validate :paid_to_account_requires_paid_from_account

  scope :active, -> { where(active: true) }
  scope :alphabetically, -> { order(Arel.sql("LOWER(name)")) }

  def cycle_start_for(date)
    date = date.to_date
    case frequency
    when "weekly"
      occurrence_at_or_before(date, step_days: 7)
    when "biweekly"
      occurrence_at_or_before(date, step_days: 14)
    when "monthly"
      Date.new(date.year, date.month, 1)
    when "quarterly"
      cycle_first_of_month(date, step_months: 3)
    when "semi_annual"
      cycle_first_of_month(date, step_months: 6)
    when "annual"
      cycle_first_of_month(date, step_months: 12)
    end
  end

  def due_date_for(date)
    cs = cycle_start_for(date)
    case frequency
    when "weekly", "biweekly"
      cs
    else
      last_day = cs.end_of_month.day
      Date.new(cs.year, cs.month, [ anchor_date.day, last_day ].min)
    end
  end

  def occurrences_in(range)
    range_start = range.first.to_date
    range_end = range.last.to_date
    results = []
    occurrence = first_occurrence_on_or_after(range_start)
    while occurrence && occurrence <= range_end
      results << occurrence
      occurrence = step_forward(occurrence)
    end
    results
  end

  def payment_for(date)
    bill_payments.find_by(period: cycle_start_for(date))
  end

  def paid?(date)
    payment_for(date).present?
  end

  def status_for(date, today: Date.current)
    return :paid if paid?(date)
    due_date_for(date) < today ? :overdue : :upcoming
  end

  # Average per-month spend, used for budgeting/insights coverage math.
  def monthly_amount
    case frequency
    when "weekly" then amount * 52 / 12.0
    when "biweekly" then amount * 26 / 12.0
    when "monthly" then amount
    when "quarterly" then amount / 3.0
    when "semi_annual" then amount / 6.0
    when "annual" then amount / 12.0
    end
  end

  def mark_paid!(date, at: Time.current)
    cycle = cycle_start_for(date)
    existing = bill_payments.find_by(period: cycle)
    return existing if existing

    transaction do
      payment = bill_payments.build(period: cycle, paid_at: at)

      if paid_from_account && paid_to_account
        transfer = Transfer::Creator.new(
          family: family,
          source_account_id: paid_from_account_id,
          destination_account_id: paid_to_account_id,
          date: at.to_date,
          amount: amount
        ).create

        raise ActiveRecord::RecordInvalid, transfer unless transfer.persisted?

        payment.entry = transfer.outflow_transaction.entry
      elsif paid_from_account
        payment.entry = paid_from_account.entries.create!(
          entryable: Transaction.new(category: category),
          name: name,
          amount: amount,
          currency: paid_from_account.currency,
          date: at.to_date,
          notes: "Bill payment"
        )
      end

      payment.save!
      payment.entry&.sync_account_later
      payment
    end
  end

  def unmark_paid!(date)
    payment_for(date)&.destroy!
  end

  private
    def occurrence_at_or_before(date, step_days:)
      diff = (date - anchor_date).to_i
      n = (diff.to_f / step_days).floor
      anchor_date + (n * step_days)
    end

    def cycle_first_of_month(date, step_months:)
      months_offset = (date.year - anchor_date.year) * 12 + (date.month - anchor_date.month)
      n = (months_offset.to_f / step_months).floor
      cycle_anchor = anchor_date >> (n * step_months)
      Date.new(cycle_anchor.year, cycle_anchor.month, 1)
    end

    def first_occurrence_on_or_after(date)
      case frequency
      when "weekly"
        first_occurrence_with_step_days(date, step_days: 7)
      when "biweekly"
        first_occurrence_with_step_days(date, step_days: 14)
      when "monthly"
        first_occurrence_with_step_months(date, step_months: 1)
      when "quarterly"
        first_occurrence_with_step_months(date, step_months: 3)
      when "semi_annual"
        first_occurrence_with_step_months(date, step_months: 6)
      when "annual"
        first_occurrence_with_step_months(date, step_months: 12)
      end
    end

    def first_occurrence_with_step_days(date, step_days:)
      diff = (date - anchor_date).to_i
      n = (diff.to_f / step_days).ceil
      anchor_date + (n * step_days)
    end

    def first_occurrence_with_step_months(date, step_months:)
      candidate = anchor_date
      months_diff = (date.year - candidate.year) * 12 + (date.month - candidate.month)
      n = (months_diff.to_f / step_months).floor
      candidate = anchor_date >> (n * step_months)
      candidate = clamp_to_month_end(candidate, anchor_date.day)
      candidate = step_forward(candidate) while candidate < date
      candidate
    end

    def clamp_to_month_end(date, day)
      last_day = date.end_of_month.day
      Date.new(date.year, date.month, [ day, last_day ].min)
    end

    def step_forward(date)
      case frequency
      when "weekly" then date + 7
      when "biweekly" then date + 14
      when "monthly" then clamp_to_month_end(date >> 1, anchor_date.day)
      when "quarterly" then clamp_to_month_end(date >> 3, anchor_date.day)
      when "semi_annual" then clamp_to_month_end(date >> 6, anchor_date.day)
      when "annual" then clamp_to_month_end(date >> 12, anchor_date.day)
      end
    end

    def paid_to_account_must_be_liability
      return unless paid_to_account
      return if paid_to_account.liability?

      errors.add(:paid_to_account_id, "must be a debt account (loan, credit card, or other liability)")
    end

    def paid_to_and_from_accounts_must_differ
      return unless paid_to_account_id && paid_from_account_id

      if paid_to_account_id == paid_from_account_id
        errors.add(:paid_to_account_id, "must be different from the paid-from account")
      end
    end

    def paid_to_account_requires_paid_from_account
      return if paid_to_account_id.blank?
      return if paid_from_account_id.present?

      errors.add(:paid_to_account_id, "requires a paid-from account so the payment can be transferred")
    end
end
