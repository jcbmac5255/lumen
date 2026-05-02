class CascadeBillPaymentOnEntryDelete < ActiveRecord::Migration[7.2]
  def up
    remove_foreign_key :bill_payments, :entries
    add_foreign_key :bill_payments, :entries, on_delete: :cascade
  end

  def down
    remove_foreign_key :bill_payments, :entries
    add_foreign_key :bill_payments, :entries
  end
end
