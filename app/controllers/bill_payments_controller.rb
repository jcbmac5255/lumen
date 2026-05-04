class BillPaymentsController < ApplicationController
  before_action :set_bill
  before_action :set_target_date

  def create
    @bill.mark_paid!(@target_date)
    redirect_back_or_to bills_path(period: @target_date.strftime("%Y-%m"))
  end

  def destroy
    @bill.unmark_paid!(@target_date)
    redirect_back_or_to bills_path(period: @target_date.strftime("%Y-%m"))
  end

  private
    def set_bill
      @bill = Current.family.bills.find(params[:bill_id])
    end

    # Accepts YYYY-MM-DD (a specific occurrence) or YYYY-MM (resolve to the
    # first occurrence in that month, for backward compat with monthly bills).
    def set_target_date
      raw = params[:period].presence
      @target_date =
        if raw.blank?
          Date.current
        elsif raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          Date.strptime(raw, "%Y-%m-%d")
        elsif raw.match?(/\A\d{4}-\d{2}\z/)
          month_start = Date.strptime(raw, "%Y-%m").beginning_of_month
          @bill.occurrences_in(month_start..month_start.end_of_month).first || month_start
        else
          Date.current
        end
    rescue ArgumentError
      @target_date = Date.current
    end
end
