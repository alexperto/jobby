class CreateJobOpportunities < ActiveRecord::Migration[8.1]
  def change
    create_table :job_opportunities do |t|
      t.string :company, null: false
      t.string :title, null: false
      t.string :location, null: false
      t.string :mode, null: false
      t.string :website, null: false
      t.string :url, null: false
      t.date :published_date
      t.text :description_summary, null: false, default: ""
      t.text :minimum_requirements
      t.string :salary
      t.string :state, null: false, default: "new"
      t.float :score
      # Normalized "company|title|location" — see JobOpportunity#set_dedup_key.
      # The unique index is the actual dedup guarantee (atomic at the DB
      # level), not just a model-level uniqueness check.
      t.string :dedup_key, null: false

      t.timestamps
    end

    add_index :job_opportunities, :dedup_key, unique: true
    add_index :job_opportunities, :state
    add_index :job_opportunities, [ :published_date, :id ]
  end
end
