class JournalEntriesController < ApplicationController
  before_action :set_journal_entry, only: %i[ show edit update destroy invalid_num_error ]
  rescue_from ActionView::Helpers::NumberHelper::InvalidNumberError, :with => :invalid_num_error

  rescue_from Pundit::NotAuthorizedError do 
    redirect_to error_path
  end

  # GET /journal_entries or /journal_entries.json
  def index
    authorize current_user, :user_not_admin?
    @journal_entries = JournalEntry.all
  end

  # GET /journal_entries/new
  def new
    authorize current_user, :user_not_admin?
    @sorted_active_accounts = Account.where(active: true).order(:account_number)
    @journal_entry = JournalEntry.new
  end

  # POST /journal_entries or /journal_entries.json
  def create
    authorize current_user, :user_not_admin?
    debit_account_ids = journal_entry_params[:debit_account].map(&:to_i)
    credit_account_ids = journal_entry_params[:credit_account].map(&:to_i)

    debit_amounts = journal_entry_params[:debit_total]
    credit_amounts = journal_entry_params[:credit_total]

    @journal_entry = JournalEntry.new(  user_id: current_user.id,
                                        debit_account: debit_account_ids,
                                        credit_account: credit_account_ids,
                                        debit_total: debit_amounts,
                                        credit_total: credit_amounts,
                                        entry_type: journal_entry_params[:entry_type],  
                                        status: "Pending",
                                        description: params[:journal_entry][:description]
                                      )
                                      
    @journal_entry.source_document.attach(params[:journal_entry][:source_document])

    error_list = valid?(debit_account_ids, credit_account_ids, debit_amounts, credit_amounts)
    error_list = balanced?(debit_amounts, credit_amounts) if !balanced?(debit_amounts, credit_amounts).nil?

    if error_list.nil?
      @journal_entry.date_added = params[:date].to_date
      
      if @journal_entry.save
        redirect_to journal_entries_path, warning: "Journal entry pending"
        User.where(userType: 2).pluck(:email).each do |email|
          ResetMailer.with(user_email: email).pending_journal_entry.deliver_now
        end
      else
        flash.now[:danger] = "#{@account.errors.first.full_message}"
        render new_journal_entry_path
      end
    else
      @journal_entry.debit_total = [debit_amounts.first]
      @journal_entry.credit_total = [credit_amounts.first]

      flash.now[:danger] = "#{error_list}"
      render new_journal_entry_path
    end
  end

  def approve
    authorize current_user, :user_manager?
    approve_entry(params[:entry].to_i)
    redirect_to journal_entries_path, success: ErrorMessage.find_by(error_name: "Journal_approved").body
  end

  def decline
    authorize current_user, :user_manager?
    decline_entry(params[:entry].to_i, params[:reason])
    redirect_to journal_entries_path, danger: ErrorMessage.find_by(error_name: "Journal_declined").body
  end

  def approve_all
    authorize current_user, :user_manager?
    @pending_entries = JournalEntry.where(status: "Pending")
    @pending_entries.each do |e|
      approve_entry(e.id)
    end
    redirect_to journal_entries_path, success: ErrorMessage.find_by(error_name: "Journal_all_approved").body
  end

  def decline_all
    authorize current_user, :user_manager?
    @pending_entries = JournalEntry.where(status: "Pending")
    @pending_entries.each do |e|
      decline_entry(e.id, "Manager has declined all entries")
    end
    redirect_to journal_entries_path, danger: ErrorMessage.find_by(error_name: "Journal_all_declined").body
  end

  def generate_closing_entry
    @service_revenue = Account.find_by(name: "Service Revenue")
    @expense_accounts = Account.where('balance > ?', 0).where(category: "Expense")
    @expense_accounts += Account.where(name: "Retained Earnings")
    @debit = @expense_accounts.pluck(:balance)
    @debit.pop
    
    @closing_journal_entry = JournalEntry.new(  user_id: current_user.id,
                                        debit_account:  [@service_revenue.id],
                                        credit_account: @expense_accounts.pluck(:id),
                                        debit_total:    [-@service_revenue.balance],
                                        credit_total:   @debit << Account.retained_earnings_value(),
                                        entry_type: "Closing",
                                        status: "Pending",
                                        description: "Closing entry created by #{current_user.username}",
                                        date_added: Time.now.to_date
                                      )

    if @closing_journal_entry.save
      redirect_to journal_entries_path, success: ErrorMessage.find_by(error_name: "journal_created_closing_entry").body
    else
      flash.now[:danger] = ErrorMessage.find_by(error_name: "journal_closing_entry_failed").body
      render new_journal_entry_path
    end
  end

  def show
    @journal_entry = JournalEntry.find_by(id: params[:id])
  end

  def reload_page
    redirect_to journal_entries_path
  end 

  private

    def approve_entry(id)
      @entry = JournalEntry.find(id)
      @entry.status = "Approved"
      @entry.save
      LedgerEntry.create_new_entry(@entry)
    end

    def decline_entry(id, reason)
      @entry = JournalEntry.find(id)
      @entry.status = "Declined"
      @entry.description += "\n (#{current_user.username} has declined this entry because: '#{reason}')"
      @entry.save
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_journal_entry
      @journal_entry = JournalEntry.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def journal_entry_params
      params.fetch(:journal_entry, {})
    end

    def valid?(debit_accounts, credit_accounts, debit, credit)
      # Checks if debit accounts are all dif
      if debit_accounts.uniq.length == debit_accounts.length
        # Checks if credit accounts are all dif
        if credit_accounts.uniq.length == credit_accounts.length
          # Checks if debit and credit accounts have same account
          if (debit_accounts - credit_accounts).count == debit_accounts.count

            # Check if debit has only 2 decimals and is not negative
            debit.each do |num|
              if num.to_f > 0
                ActionController::Base.helpers.number_to_currency(num, precision: 2, raise: true)
              else
                return "Debit amount can not be 0"
              end
            end

            # Check if credit has only 2 decimals and converts it to currency
            credit.each do |num|
              if num.to_f > 0
                ActionController::Base.helpers.number_to_currency(num, precision: 2, raise: true)
              else
                return "Credit amount can not be 0"
              end
            end

            return nil
          else
            return "You can not debit and credit from the same account"
          end
        else
          return "You can not credit from the same account twice"
        end
      else
        return "You can not debit from the same account twice"
      end
    end

    def balanced?(debit, credit)
      debit_sum = 0
      debit.each do |num|
        debit_sum += ActionController::Base.helpers.number_with_precision(num, precision: 2).to_f
      end  

      credit_sum = 0
      credit.each do |num|
        credit_sum += ActionController::Base.helpers.number_with_precision(num, precision: 2).to_f
      end 

      if debit_sum == credit_sum
        return nil
      else
        return "Total Debits and Credits are not balanced: (Debit = $#{debit_sum}, Credit = $#{credit_sum})"
      end
    end
    
    def invalid_num_error
      flash.now[:danger] = "Debit/Credit value is not a correct number"
      render new_journal_entry_path
    end
end
