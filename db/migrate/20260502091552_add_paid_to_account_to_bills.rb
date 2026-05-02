class AddPaidToAccountToBills < ActiveRecord::Migration[7.2]
  def change
    add_reference :bills, :paid_to_account, type: :uuid, foreign_key: { to_table: :accounts }, null: true
  end
end
