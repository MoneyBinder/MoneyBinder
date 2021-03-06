class Account < ApplicationRecord
  validates :name,           uniqueness: true
  validates :account_number, uniqueness: true
  validates :account_number, numericality: { only_integer: true }
  validates :initial_balance, format: {with: /\A\d+(?:\.\d{0,2})?\z/}, numericality: { less_than: 1000000000 }
  has_one :user
  has_many :ledger_entries

  def self.calculate_balance(account)
    account.initial_balance + (account.debit - account.credit)
  end

  def self.update_account_balance(accountId)
    account = Account.find_by(id: accountId)
    ledgers_for_account = LedgerEntry.where(account_id: accountId)
    debit_sum = ledgers_for_account.pluck(:debit).reduce(0, :+)
    credit_sum = ledgers_for_account.pluck(:credit).reduce(0, :+)
    init_balance = account.initial_balance

    account.balance = (init_balance + (debit_sum - credit_sum))
    account.save
    return account.balance
  end

  def self.retained_earnings_value
    non_zero_accounts = Account.where('balance != ?', 0 )
    revenue_accounts = Account.find_by(name: "Service Revenue")
    total_revenues = revenue_accounts.balance

    expense_accounts = non_zero_accounts.where(category: "Expense")
    total_expenses = expense_accounts.pluck(:balance).sum

    net_income = total_revenues.abs - total_expenses

    beginning_balance = 0
    less_drawings = Account.where(account_number: [205, 206]).pluck(:balance).sum   #Sums the balance of Common "Dividends Payable" and "Preferred Dividends Payable"
    @ending_balance = (beginning_balance + net_income) - less_drawings
      if Account.find_by(account_number: 325).balance.abs > 0
        return(Account.find_by(account_number: 325).balance.abs)
      else 
        return(@ending_balance)
      end
  end
end