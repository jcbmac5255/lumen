class AddFrequencyToBills < ActiveRecord::Migration[7.2]
  def up
    add_column :bills, :frequency, :string, default: "monthly", null: false
    add_column :bills, :anchor_date, :date

    today = Date.current
    Bill.reset_column_information
    Bill.find_each do |bill|
      day = bill.read_attribute(:due_day) || today.day
      last_day = today.end_of_month.day
      anchor = Date.new(today.year, today.month, [ day, last_day ].min)
      anchor = anchor.next_month if anchor < today
      bill.update_columns(anchor_date: anchor)
    end

    change_column_null :bills, :anchor_date, false
    remove_column :bills, :due_day
  end

  def down
    add_column :bills, :due_day, :integer
    Bill.reset_column_information
    Bill.find_each do |bill|
      bill.update_columns(due_day: bill.anchor_date.day)
    end
    change_column_null :bills, :due_day, false
    remove_column :bills, :anchor_date
    remove_column :bills, :frequency
  end
end
