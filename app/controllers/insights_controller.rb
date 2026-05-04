class InsightsController < ApplicationController
  def show
    @period = parse_period(params[:period])
    @prior_period = prior_period_for(@period)

    statement = Current.family.income_statement

    @income = statement.income_totals(period: @period)
    @expenses = statement.expense_totals(period: @period)

    @prior_income = statement.income_totals(period: @prior_period)
    @prior_expenses = statement.expense_totals(period: @prior_period)

    @income_rows = top_level_rows(@income.category_totals)
    @expense_rows = top_level_rows(@expenses.category_totals)

    @currency = Current.family.currency
    @top_merchants = top_merchants(@period)
    @largest_transactions = largest_transactions(@period)
    @spend_by_dow = spend_by_day_of_week(@period)
    @monthly_trend = monthly_trend(months: 12)
    @recurring = detect_recurring(lookback_days: 90)
    @bills_coverage = bills_coverage_for(@period)
    @velocity = spending_velocity_for(@period, @expenses)
    @outliers = outlier_transactions(@period)
    @income_diversity = income_diversity_for(@income)
    @account_cashflow = account_cashflow_for(@period)

    @breadcrumbs = [ [ "Home", root_path ], [ "Insights", nil ] ]
  end

  def narrative
    @period = parse_period(params[:period])
    @narrative = Insights::Narrator.new(Current.family, @period).call
    render layout: false
  end

  private
    def parse_period(key)
      return Period.last_30_days if key.blank?
      Period.from_key(key)
    rescue Period::InvalidKeyError
      Period.last_30_days
    end

    def prior_period_for(period)
      length_days = (period.end_date - period.start_date).to_i + 1
      Period.custom(
        start_date: period.start_date - length_days,
        end_date: period.start_date - 1
      )
    end

    def top_level_rows(category_totals)
      category_totals
        .reject { |ct| ct.category.subcategory? }
        .reject { |ct| ct.total.zero? }
        .sort_by { |ct| -ct.total.to_f }
    end

    def largest_transactions(period, limit: 10)
      Current.family.transactions
        .visible
        .joins(:entry)
        .includes(:category, entry: :account)
        .where(entries: { date: period.start_date..period.end_date })
        .order(Arel.sql("ABS(entries.amount) DESC"))
        .limit(limit)
    end

    def spend_by_day_of_week(period)
      # Sum positive entry amounts (expenses) grouped by day-of-week (0=Sunday).
      rows = Current.family.transactions
        .visible
        .joins(:entry)
        .where(entries: { date: period.start_date..period.end_date })
        .where("entries.amount > 0")
        .group(Arel.sql("EXTRACT(DOW FROM entries.date)::int"))
        .sum("entries.amount")

      # Always return all 7 days even if empty
      (0..6).each_with_object({}) { |d, h| h[d] = (rows[d] || 0).to_f }
    end

    # Last N months of income/expense totals for a side-by-side bar chart.
    def monthly_trend(months: 12)
      start = (months - 1).months.ago.beginning_of_month.to_date
      finish = Date.current.end_of_month

      rows = Current.family.transactions
        .visible
        .joins(:entry)
        .where(entries: { date: start..finish })
        .where("transactions.kind NOT IN ('funds_movement', 'cc_payment', 'loan_payment')")
        .group(
          Arel.sql("DATE_TRUNC('month', entries.date)"),
          Arel.sql("CASE WHEN entries.amount > 0 THEN 'expense' ELSE 'income' END")
        )
        .sum("ABS(entries.amount)")

      months_seq = (0...months).map { |i| (months - 1 - i).months.ago.beginning_of_month.to_date }
      months_seq.map do |month|
        income = (rows[[ month.to_time, "income" ]] || 0).to_f
        expense = (rows[[ month.to_time, "expense" ]] || 0).to_f
        { month: month, income: income, expense: expense, net: income - expense }
      end
    end

    # Find merchants you spend on every month — likely subscriptions / recurring bills.
    # Heuristic: at least 3 expense transactions in the lookback window from the same merchant,
    # with amounts within 25% of each other.
    def detect_recurring(lookback_days: 90)
      cutoff = lookback_days.days.ago.to_date

      grouped = Current.family.transactions
        .visible
        .joins(:entry, :merchant)
        .where(entries: { date: cutoff..Date.current })
        .where("entries.amount > 0")
        .where.not(merchant_id: nil)
        .select(
          "transactions.merchant_id",
          "merchants.name AS merchant_name",
          "entries.amount AS amount",
          "entries.date AS date"
        )
        .to_a
        .group_by(&:merchant_id)

      grouped.map do |merchant_id, txns|
        next nil if txns.size < 3
        amounts = txns.map { |t| t.amount.to_f }
        avg = amounts.sum / amounts.size
        next nil if avg.zero?
        max_dev = amounts.map { |a| (a - avg).abs / avg }.max
        next nil if max_dev > 0.25 # too variable to call "recurring"

        # Estimate monthly cost: total spend over lookback ÷ lookback days × 30
        total = amounts.sum
        monthly_estimate = total / lookback_days * 30

        {
          merchant_name: txns.first.merchant_name,
          count: txns.size,
          avg: avg,
          monthly_estimate: monthly_estimate,
          last_seen: txns.map(&:date).max
        }
      end.compact.sort_by { |r| -r[:monthly_estimate] }
    end

    # Of this period's expenses, what fraction is covered by tracked bills?
    def bills_coverage_for(period)
      return nil unless Current.family.respond_to?(:bills)

      length_months = ((period.end_date - period.start_date).to_f + 1) / 30.0
      return nil if length_months < 0.1

      monthly_bills = Current.family.bills.active.to_a.sum { |b| b.monthly_amount.to_f }
      bills_total = monthly_bills * length_months
      total_expenses = @expenses.total.to_f
      return nil if total_expenses.zero?

      pct = [ (bills_total / total_expenses * 100).round(1), 100.0 ].min
      {
        bills_total: bills_total,
        expenses_total: total_expenses,
        pct: pct,
        active_bills_count: Current.family.bills.active.count
      }
    end

    # If the period covers a still-in-progress month or year, project end-of-period spend.
    def spending_velocity_for(period, expenses)
      return nil unless %w[current_month current_year].include?(period.key.to_s)

      today = Date.current
      length_days = (period.end_date - period.start_date).to_i + 1
      elapsed = (today - period.start_date).to_i + 1
      remaining = (period.end_date - today).to_i
      return nil if elapsed <= 0 || remaining <= 0

      so_far = expenses.total.to_f
      projected = so_far / elapsed * length_days

      {
        so_far: so_far,
        projected: projected,
        days_elapsed: elapsed,
        days_remaining: remaining,
        period_label: period.label
      }
    end

    # Transactions in this period whose abs amount is far above their category's recent baseline.
    def outlier_transactions(period, lookback_days: 90, min_multiplier: 3.0)
      cutoff = lookback_days.days.ago.to_date

      # Build per-category median for expense transactions in the lookback window
      baseline_rows = Current.family.transactions
        .visible
        .joins(:entry)
        .where(entries: { date: cutoff..Date.current })
        .where("entries.amount > 0")
        .where.not(category_id: nil)
        .pluck(:category_id, "entries.amount")

      baselines = baseline_rows.group_by(&:first).transform_values do |rows|
        amounts = rows.map { |r| r[1].to_f }.sort
        amounts[amounts.size / 2] # median
      end

      Current.family.transactions
        .visible
        .joins(:entry)
        .includes(:category, entry: :account)
        .where(entries: { date: period.start_date..period.end_date })
        .where("entries.amount > 0")
        .where.not(category_id: nil)
        .filter_map do |txn|
          baseline = baselines[txn.category_id]
          next nil unless baseline && baseline > 0
          ratio = txn.entry.amount.to_f / baseline
          next nil if ratio < min_multiplier
          { transaction: txn, ratio: ratio.round(1), baseline: baseline }
        end
        .sort_by { |r| -r[:ratio] }
        .first(5)
    end

    def income_diversity_for(income)
      rows = income.category_totals
        .reject { |ct| ct.category.subcategory? || ct.total.zero? }
        .sort_by { |ct| -ct.total.to_f }
      return nil if rows.empty?

      total = income.total.to_f
      top_share = total.zero? ? 0 : (rows.first.total.to_f / total * 100).round(1)

      {
        sources_count: rows.size,
        top_category: rows.first.category,
        top_share: top_share,
        concentrated: top_share >= 80
      }
    end

    # Net flow per account during the period: positive = money came in, negative = money went out.
    # Excludes transfers (so we see real income/expense flow per account, not movement).
    def account_cashflow_for(period)
      rows = Current.family.transactions
        .visible
        .joins(:entry)
        .where(entries: { date: period.start_date..period.end_date })
        .where("transactions.kind NOT IN ('funds_movement', 'cc_payment', 'loan_payment')")
        .group("entries.account_id")
        .sum("entries.amount")

      rows.map do |account_id, sum|
        # entries.amount: positive = outflow (expense), negative = inflow (income).
        # Net flow INTO the account = -sum.
        net = -sum.to_f
        account = Current.family.accounts.find_by(id: account_id)
        next nil unless account
        { account: account, net: net }
      end.compact.sort_by { |r| -r[:net].abs }.first(8)
    end

    def top_merchants(period, limit: 10)
      Current.family.transactions
        .visible
        .joins(:entry)
        .where(entries: { date: period.start_date..period.end_date })
        .where("entries.amount > 0") # expenses (positive amounts on the entry)
        .where.not(merchant_id: nil)
        .group(:merchant_id)
        .select("merchant_id, SUM(entries.amount) AS total, COUNT(*) AS txn_count")
        .order("total DESC")
        .limit(limit)
        .map do |row|
          merchant = Merchant.find_by(id: row.merchant_id)
          next nil unless merchant
          { merchant: merchant, total: row.total, count: row.txn_count }
        end
        .compact
    end
end
