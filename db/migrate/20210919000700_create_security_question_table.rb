class CreateSecurityQuestionTable < ActiveRecord::Migration[6.1]
  def change
    create_table :security_questions do |t|
      t.text :question
      t.timestamps null: false
    end
  end
end
