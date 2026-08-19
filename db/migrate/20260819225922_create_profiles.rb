class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.text :resume_text, null: false, default: ""
      t.json :characteristics, null: false, default: {}
      t.json :target_roles, null: false, default: []
      t.integer :min_salary
      t.json :preferred_cities, null: false, default: []
      t.json :preferred_modes, null: false, default: []

      t.timestamps
    end
  end
end
