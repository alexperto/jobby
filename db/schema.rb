# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_19_225923) do
  create_table "job_opportunities", force: :cascade do |t|
    t.string "company", null: false
    t.datetime "created_at", null: false
    t.string "dedup_key", null: false
    t.text "description_summary", default: "", null: false
    t.string "location", null: false
    t.text "minimum_requirements"
    t.string "mode", null: false
    t.date "published_date"
    t.string "salary"
    t.float "score"
    t.string "state", default: "new", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.string "website", null: false
    t.index ["dedup_key"], name: "index_job_opportunities_on_dedup_key", unique: true
    t.index ["published_date", "id"], name: "index_job_opportunities_on_published_date_and_id"
    t.index ["state"], name: "index_job_opportunities_on_state"
  end

  create_table "profiles", force: :cascade do |t|
    t.json "characteristics", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "min_salary"
    t.json "preferred_cities", default: [], null: false
    t.json "preferred_modes", default: [], null: false
    t.text "resume_text", default: "", null: false
    t.json "target_roles", default: [], null: false
    t.datetime "updated_at", null: false
  end
end
