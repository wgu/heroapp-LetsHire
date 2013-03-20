class CreateDepartments < ActiveRecord::Migration
  def change
    create_table :departments do |t|
      t.string :name, null: false
      t.string :description
    end

    add_index :departments, :name, unique: true
  end
end
