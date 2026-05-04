require "test_helper"

class BillTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @checking = accounts(:depository)
    @credit_card = accounts(:credit_card)
    @loan = accounts(:loan)

    @bill = @family.bills.create!(
      name: "Credit Card Payment",
      amount: 250,
      currency: "USD",
      anchor_date: Date.new(2026, 5, 15)
    )
  end

  test "monthly cycle_start_for is start of containing month" do
    assert_equal Date.new(2026, 5, 1), @bill.cycle_start_for(Date.new(2026, 5, 22))
    assert_equal Date.new(2026, 6, 1), @bill.cycle_start_for(Date.new(2026, 6, 1))
  end

  test "monthly occurrences yield one date per visible month" do
    occurrences = @bill.occurrences_in(Date.new(2026, 5, 1)..Date.new(2026, 5, 31))
    assert_equal [ Date.new(2026, 5, 15) ], occurrences

    occurrences = @bill.occurrences_in(Date.new(2026, 5, 1)..Date.new(2026, 7, 31))
    assert_equal [ Date.new(2026, 5, 15), Date.new(2026, 6, 15), Date.new(2026, 7, 15) ], occurrences
  end

  test "weekly bill yields four-or-five occurrences per month" do
    weekly = @family.bills.create!(name: "Gym", amount: 20, currency: "USD",
                                   frequency: "weekly", anchor_date: Date.new(2026, 5, 4))
    occurrences = weekly.occurrences_in(Date.new(2026, 5, 1)..Date.new(2026, 5, 31))
    assert_equal [ Date.new(2026, 5, 4), Date.new(2026, 5, 11),
                   Date.new(2026, 5, 18), Date.new(2026, 5, 25) ], occurrences
  end

  test "biweekly cycle_start_for snaps to anchor + 14n" do
    biweekly = @family.bills.create!(name: "Mortgage", amount: 800, currency: "USD",
                                     frequency: "biweekly", anchor_date: Date.new(2026, 5, 1))
    assert_equal Date.new(2026, 5, 15), biweekly.cycle_start_for(Date.new(2026, 5, 20))
    assert_equal Date.new(2026, 5, 1),  biweekly.cycle_start_for(Date.new(2026, 5, 14))
  end

  test "quarterly bill only appears on its anchor cycle months" do
    quarterly = @family.bills.create!(name: "Insurance", amount: 600, currency: "USD",
                                      frequency: "quarterly", anchor_date: Date.new(2026, 3, 10))
    assert_empty quarterly.occurrences_in(Date.new(2026, 5, 1)..Date.new(2026, 5, 31))
    assert_equal [ Date.new(2026, 6, 10) ],
                 quarterly.occurrences_in(Date.new(2026, 6, 1)..Date.new(2026, 6, 30))
  end

  test "annual bill only appears in its anchor month" do
    annual = @family.bills.create!(name: "Domain", amount: 12, currency: "USD",
                                   frequency: "annual", anchor_date: Date.new(2026, 8, 4))
    assert_empty annual.occurrences_in(Date.new(2026, 5, 1)..Date.new(2026, 5, 31))
    assert_equal [ Date.new(2026, 8, 4) ],
                 annual.occurrences_in(Date.new(2026, 8, 1)..Date.new(2026, 8, 31))
  end

  test "monthly_amount normalizes to a per-month figure" do
    weekly = @family.bills.new(amount: 10, frequency: "weekly")
    annual = @family.bills.new(amount: 120, frequency: "annual")
    assert_in_delta 43.33, weekly.monthly_amount, 0.01
    assert_in_delta 10.00, annual.monthly_amount, 0.01
  end

  test "paid_to_account must be a liability" do
    @bill.paid_from_account = @checking
    @bill.paid_to_account = @checking
    assert_not @bill.valid?
    assert_includes @bill.errors[:paid_to_account_id], "must be a debt account (loan, credit card, or other liability)"
  end

  test "paid_to_account and paid_from_account must differ" do
    @bill.paid_from_account = @credit_card
    @bill.paid_to_account = @credit_card
    assert_not @bill.valid?
    assert_includes @bill.errors[:paid_to_account_id], "must be different from the paid-from account"
  end

  test "paid_to_account requires paid_from_account" do
    @bill.paid_to_account = @credit_card
    assert_not @bill.valid?
    assert_includes @bill.errors[:paid_to_account_id], "requires a paid-from account so the payment can be transferred"
  end

  test "mark_paid! creates a linked transfer when both accounts set" do
    @bill.update!(paid_from_account: @checking, paid_to_account: @credit_card)

    payment = nil
    assert_difference [ "BillPayment.count", "Transfer.count" ], 1 do
      assert_difference "Entry.count", 2 do
        payment = @bill.mark_paid!(Date.current)
      end
    end

    transfer = payment.entry.transaction.transfer
    assert transfer.present?, "expected outflow entry to be linked to a transfer"
    assert_equal @checking, transfer.from_account
    assert_equal @credit_card, transfer.to_account
    assert_equal "cc_payment", transfer.outflow_transaction.kind
  end

  test "mark_paid! with loan destination uses loan_payment kind" do
    @bill.update!(paid_from_account: @checking, paid_to_account: @loan)

    payment = @bill.mark_paid!(Date.current)
    transfer = payment.entry.transaction.transfer

    assert_equal "loan_payment", transfer.outflow_transaction.kind
  end

  test "mark_paid! with only paid_from_account creates a single entry" do
    @bill.update!(paid_from_account: @checking)

    assert_difference "BillPayment.count", 1 do
      assert_difference "Entry.count", 1 do
        assert_no_difference "Transfer.count" do
          @bill.mark_paid!(Date.new(2026, 5, 15))
        end
      end
    end
  end

  test "mark_paid! without any account just records the payment" do
    assert_difference "BillPayment.count", 1 do
      assert_no_difference [ "Entry.count", "Transfer.count" ] do
        @bill.mark_paid!(Date.new(2026, 5, 15))
      end
    end
  end

  test "unmark_paid! destroys the transfer leg recorded on the bill payment" do
    @bill.update!(paid_from_account: @checking, paid_to_account: @credit_card)
    payment = @bill.mark_paid!(Date.current)
    outflow_entry_id = payment.entry.id

    @bill.unmark_paid!(Date.current)

    assert_nil BillPayment.find_by(id: payment.id)
    assert_nil Entry.find_by(id: outflow_entry_id)
  end

  test "unmark_paid! removes the single entry for non-transfer payments" do
    @bill.update!(paid_from_account: @checking)
    @bill.mark_paid!(Date.new(2026, 5, 15))

    assert_difference [ "BillPayment.count", "Entry.count" ], -1 do
      @bill.unmark_paid!(Date.current)
    end
  end

  test "destroying the bill removes its single-entry payments" do
    @bill.update!(paid_from_account: @checking)
    payment = @bill.mark_paid!(Date.current)
    entry_id = payment.entry.id

    @bill.destroy!

    assert_nil BillPayment.find_by(id: payment.id)
    assert_nil Entry.find_by(id: entry_id)
  end

  test "deleting the linked entry removes the bill payment marker" do
    @bill.update!(paid_from_account: @checking)
    payment = @bill.mark_paid!(Date.current)

    assert_difference [ "Entry.count", "BillPayment.count" ], -1 do
      payment.entry.destroy!
    end

    assert_not @bill.reload.paid?(Date.current)
  end

  test "destroying the bill removes both legs of transfer payments" do
    @bill.update!(paid_from_account: @checking, paid_to_account: @credit_card)
    payment = @bill.mark_paid!(Date.current)
    outflow_entry = payment.entry
    inflow_entry = outflow_entry.transaction.transfer.inflow_transaction.entry

    @bill.destroy!

    assert_nil Entry.find_by(id: outflow_entry.id)
    assert_nil Entry.find_by(id: inflow_entry.id)
  end
end
