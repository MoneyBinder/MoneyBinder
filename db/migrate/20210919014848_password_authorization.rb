class PasswordAuthorization < ActiveRecord::Migration[6.1]
  def change
    create_table :password_authorizations do |t|
      t.references :user, foreign_key: true
      t.references :security_questions, foreign_key: true
      t.text :answer

      t.timestamps null: false
    end
  end
end
