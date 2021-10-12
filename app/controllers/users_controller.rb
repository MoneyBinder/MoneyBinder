class UsersController < ApplicationController
  # will bypass :authorized which will allow the user login/signup
  skip_before_action :authorized, only: [:new, :create]

  def new
    @user = User.new
  end

  def create
    user_name = User.create_username(params[:firstName], params[:lastName], Time.zone.now)
    pass_check = User.valid_pass?(params[:password])
    password_update = Time.now

    if pass_check.empty? && !user_name.nil?
      @user = User.new(user_params)
      @user.username = user_name
      @user.passUpdatedAt = password_update

      if @user.save 
        initialize_security_question(@user, params[:security_question_1][:id], params[:security_question_answer])
        redirect_to user_management_path, success: ErrorMessage.find_by(error_name: "user_created").body 
      else 
        redirect_to new_user_path, danger: "#{@user.errors.full_messages.first}"
      end
    else
      redirect_to new_user_path, danger: "#{pass_check}"
    end
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:user_id].to_i)
    userType = params[:userType].to_i

    if params[:active].nil?
      active = false
    else
      active = true
    end

    # Manages users suspention time
    suspend_time = Time.now.to_date
    if params[:reset_suspension] != "true" && !params[:suspend_time].nil?
      date_params = params[:suspend_time]
      date = DateTime.new(date_params["(1i)"].to_i, date_params["(2i)"].to_i, date_params["(3i)"].to_i, date_params["(4i)"].to_i, date_params["(5i)"].to_i)
      if date > Time.now.to_date
        suspend_time = date
      end
    end

    if @user.update(username: params[:username],firstName: params[:firstName], lastName: params[:lastName], email: params[:email], phoneNum: params[:phoneNum], address: params[:address], userType: userType, suspendedTill: suspend_time, active: active)
      auth_id = @user.password_authorization_ids.first
      PasswordAuthorization.update(auth_id, answer: params[:security_question_answer])
      past_user_status = @user.active
      @user.reload
      
      # If Admin activates a new users account it sents email to that user
      if @user.active != past_user_status && @user.active
        ResetMailer.with(user: @user).account_activated.deliver_now
      end

      # If user deactiviats own account, system kicks user out 
      if (!@user.active && (@user == current_user)) || @user.suspendedTill > Time.now
        redirect_to '/logout'
      else
        redirect_to user_management_path, success: ErrorMessage.find_by(error_name: "user_updated").body
      end
    else
      redirect_to edit_user_path(@user), danger: "#{@user.errors.full_messages.first}"
    end
  end

  def administrator_email
    @selected_user = User.find(params[:user][:user_id].to_i)
    @subject_text = params[:subject]
    @body_text = params[:body]
    ResetMailer.with(user: @selected_user, subject: @subject_text, body: @body_text).send_this.deliver_now
    redirect_to user_management_path, success: ErrorMessage.find_by(error_name: "email_sent").body
  end

  private

  def user_params
    params.permit(:firstName, :lastName, :user_name, :password, :address, :email, :phoneNum, :dob, :userType, :active)    
  end

  def initialize_security_question(user, question_id, answer)
    PasswordAuthorization.create(user_id: user.id, security_question_id: question_id.to_i, answer: answer)
  end
end