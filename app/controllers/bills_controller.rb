class BillsController < ApplicationController
  before_action :set_bill, only: %i[edit update destroy]

  def index
    @period = parse_period(params[:period])
    @period_range = @period..@period.end_of_month
    @bills = Current.family.bills.active.alphabetically.includes(:category, :bill_payments)
    @occurrences = @bills.flat_map { |bill| bill.occurrences_in(@period_range).map { |date| [ bill, date ] } }
    @previous_period = (@period - 1.month).beginning_of_month
    @next_period = (@period + 1.month).beginning_of_month
  end

  def new
    @bill = Current.family.bills.new(
      currency: Current.family.currency,
      active: true,
      frequency: "monthly",
      anchor_date: Date.current
    )
  end

  def create
    @bill = Current.family.bills.new(bill_params)
    @bill.currency ||= Current.family.currency

    if @bill.save
      respond_to do |format|
        format.html { redirect_back_or_to bills_path, notice: "Bill created" }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, bills_path) }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @bill.update(bill_params)
      respond_to do |format|
        format.html { redirect_back_or_to bills_path, notice: "Bill updated" }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, bills_path) }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @bill.destroy
    redirect_to bills_path, notice: "Bill deleted"
  end

  private
    def set_bill
      @bill = Current.family.bills.find(params[:id])
    end

    def bill_params
      params.require(:bill).permit(:name, :amount, :frequency, :anchor_date, :category_id, :paid_from_account_id, :paid_to_account_id, :notes, :active)
    end

    def parse_period(param)
      return Date.current.beginning_of_month if param.blank?
      Date.strptime(param, "%Y-%m").beginning_of_month
    rescue ArgumentError
      Date.current.beginning_of_month
    end
end
