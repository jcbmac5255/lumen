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
      due_day: 15
    )
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
          @bill.mark_paid!(Date.current)
        end
      end
    end
  end

  test "mark_paid! without any account just records the payment" do
    assert_difference "BillPayment.count", 1 do
      assert_no_difference [ "Entry.count", "Transfer.count" ] do
        @bill.mark_paid!(Date.current)
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
    @bill.mark_paid!(Date.current)

    assert_difference [ "BillPayment.count", "Entry.count" ], -1 do
      @bill.unmark_paid!(Date.current)
    end
  end
end
