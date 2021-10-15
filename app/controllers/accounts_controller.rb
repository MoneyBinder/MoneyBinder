class AccountsController < ApplicationController
  before_action :set_account, only: %i[ show edit update destroy ]
  
  rescue_from Pundit::NotAuthorizedError do 
    redirect_to homepage_path, danger: "You are not authorized to preform this action."
  end

  # GET /accounts or /accounts.json
  def index
    @accounts = Account.all
    if params[:search_accounts]
      @accounts = Account.search(params[:search_accounts])
      if @accounts.empty?
        flash[:warning] = ErrorMessage.find_by(error_name: "account_not_found").body
      else
        flash.clear
      end
    end
  end

  # GET /accounts/1 or /accounts/1.json
  def show
  end

  # GET /accounts/new
  def new
    @account = Account.new
  end

  # GET /accounts/1/edit
  def edit
    authorize @account, :user_admin?
  end

  # POST /accounts or /accounts.json
  def create
    @account = Account.new(account_params)
    @account.user_id = current_user.id
    @account.balance = calculate_balance(@account)
    if @account.initial_balance > 0 && params[:account][:active] == "0"
      flash.now[:danger] = ErrorMessage.find_by(error_name: "can_not_deactivate_account").body
      render new_account_path
    else
      if @account.save
        create_event_log("", @account, "Added")
        redirect_to accounts_path, success: ErrorMessage.find_by(error_name: "account_created").body
      else
        flash.now[:danger] = "#{@account.errors.first.full_message}"
        render new_account_path
      end
    end
  end

  # PATCH/PUT /accounts/1 or /accounts/1.json
  def update      
    @account_before = @account.to_json
    before_active_status = @account.active

    # Checks if account has money and if active is false
    if account_empty?(@account, params[:account][:initial_balance]) && params[:account][:active] == "0"
      redirect_to edit_account_path(@account), danger: ErrorMessage.find_by(error_name: "can_not_deactivate_account").body
    else
      if @account.update(account_params)
        changed_active = @account.active_changed?
        @account.balance = calculate_balance(@account)
        @account.save
        @account_after = @account.to_json

        # Checks if user deactivated account and creates a log
        after_active_status = @account.active
        if before_active_status && !after_active_status
          create_event_log(@account_before, @account_after, "Deactivated")
        else
          create_event_log(@account_before, @account_after, "Modified")
        end
        redirect_to accounts_path, success: ErrorMessage.find_by(error_name: "account_updated").body
      else
        redirect_to edit_account_path(@account), danger: "#{@account.errors.first.full_message}"
      end
    end
  end

  # DELETE /accounts/1 or /accounts/1.json
  def destroy
    create_event_log(@account, "", "Deactivated")
    @account.destroy
    redirect_to accounts_path, success: ErrorMessage.find_by(error_name: "account_deleted").body
  end

  def ledger
    @acc_num = params[:account_number]
  end
  
  private
    # Use callbacks to share common setup or constraints between actions.
    def set_account
      @account = Account.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def account_params
      params.fetch(:account, {}).permit!
    end

    def calculate_balance(account)
      account.initial_balance + (account.debit - account.credit)
    end

    def account_empty?(account, new_initial_balance)
      account.initial_balance = new_initial_balance   
      return calculate_balance(account) > 0
    end

    def create_event_log(before, after, type)
      if type == "Added"
        EventLog.new( account_name: after.name, 
                      user_name: current_user.username, 
                      event_type: type, 
                      account_before: before, 
                      account_after: after.to_json
                    ).save

      elsif type == "Deactivated"
        EventLog.new( account_name: JSON.parse(before, object_class: Account).name, 
                      user_name: current_user.username, 
                      event_type: type, 
                      account_before: before, 
                      account_after: after
                    ).save
      
      elsif type == "Modified"
        EventLog.new( account_name: JSON.parse(before, object_class: Account).name, 
                      user_name: current_user.username, 
                      event_type: type, 
                      account_before: before, 
                      account_after: after
                    ).save
      end
    end
end
