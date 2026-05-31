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

ActiveRecord::Schema[8.1].define(version: 2026_05_31_000716) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "group_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "group_id", null: false
    t.datetime "joined_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["group_id", "user_id"], name: "index_group_memberships_on_group_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_group_memberships_on_user_id"
  end

  create_table "groups", force: :cascade do |t|
    t.string "code", limit: 8, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.boolean "is_general_pool", default: false, null: false
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_groups_on_code", unique: true
    t.index ["deleted_at"], name: "index_groups_on_deleted_at"
    t.index ["is_general_pool"], name: "index_groups_on_single_general_pool", unique: true, where: "(is_general_pool = true)"
    t.index ["owner_id"], name: "index_groups_on_owner_id"
  end

  create_table "matches", force: :cascade do |t|
    t.bigint "advancing_team_id"
    t.integer "away_score", default: 0, null: false
    t.bigint "away_team_id", null: false
    t.integer "bracket_position"
    t.datetime "created_at", null: false
    t.jsonb "events_log", default: [], null: false
    t.string "external_id", null: false
    t.bigint "feeds_into_match_id"
    t.integer "feeds_into_slot"
    t.string "group"
    t.integer "home_score", default: 0, null: false
    t.bigint "home_team_id", null: false
    t.datetime "kickoff_at", null: false
    t.datetime "last_synced_at"
    t.integer "minute"
    t.datetime "original_kickoff_at", null: false
    t.string "phase", null: false
    t.string "status", default: "scheduled", null: false
    t.bigint "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["advancing_team_id"], name: "index_matches_on_advancing_team_id"
    t.index ["away_team_id"], name: "index_matches_on_away_team_id"
    t.index ["external_id"], name: "index_matches_on_external_id", unique: true
    t.index ["feeds_into_match_id"], name: "index_matches_on_feeds_into_match_id"
    t.index ["home_team_id"], name: "index_matches_on_home_team_id"
    t.index ["kickoff_at"], name: "index_matches_on_kickoff_at"
    t.index ["last_synced_at"], name: "index_matches_on_last_synced_at"
    t.index ["status"], name: "index_matches_on_status"
    t.index ["tournament_id", "group"], name: "index_matches_on_tournament_id_and_group"
    t.index ["tournament_id", "phase"], name: "index_matches_on_tournament_id_and_phase"
    t.index ["tournament_id"], name: "index_matches_on_tournament_id"
    t.check_constraint "home_team_id <> away_team_id", name: "matches_home_and_away_differ"
  end

  create_table "phase_multipliers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "multiplier", precision: 4, scale: 2, default: "1.0", null: false
    t.string "phase", null: false
    t.datetime "updated_at", null: false
    t.index ["phase"], name: "index_phase_multipliers_on_phase", unique: true
  end

  create_table "players", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "name", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_players_on_external_id", unique: true
    t.index ["team_id"], name: "index_players_on_team_id"
  end

  create_table "prediction_scores", force: :cascade do |t|
    t.jsonb "breakdown", default: {}, null: false
    t.datetime "computed_at", null: false
    t.datetime "created_at", null: false
    t.decimal "multiplier", precision: 4, scale: 2, default: "1.0", null: false
    t.integer "points_advance", default: 0, null: false
    t.integer "points_result", default: 0, null: false
    t.bigint "prediction_id", null: false
    t.integer "total_points", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["computed_at"], name: "index_prediction_scores_on_computed_at"
    t.index ["prediction_id"], name: "index_prediction_scores_on_prediction_id", unique: true
  end

  create_table "predictions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "locked_at"
    t.bigint "match_id", null: false
    t.bigint "predicted_advancing_team_id"
    t.integer "predicted_away_score", null: false
    t.integer "predicted_home_score", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["match_id"], name: "index_predictions_on_match_id"
    t.index ["predicted_advancing_team_id"], name: "index_predictions_on_predicted_advancing_team_id"
    t.index ["user_id", "match_id"], name: "index_predictions_on_user_id_and_match_id", unique: true
  end

  create_table "ranking_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "group_id"
    t.integer "points", null: false
    t.integer "rank_position", null: false
    t.datetime "snapshot_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["group_id"], name: "index_ranking_snapshots_on_group_id"
    t.index ["snapshot_at", "group_id", "rank_position"], name: "index_ranking_snapshots_on_snapshot_group_rank"
    t.index ["user_id", "snapshot_at"], name: "index_ranking_snapshots_on_user_id_and_snapshot_at"
  end

  create_table "scoring_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "points", default: 0, null: false
    t.string "rule_type", null: false
    t.datetime "updated_at", null: false
    t.index ["rule_type"], name: "index_scoring_rules_on_rule_type", unique: true
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "teams", force: :cascade do |t|
    t.string "code3", limit: 3, null: false
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.string "flag_url"
    t.string "name", null: false
    t.bigint "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_teams_on_external_id", unique: true
    t.index ["tournament_id", "code3"], name: "index_teams_on_tournament_id_and_code3", unique: true
    t.index ["tournament_id"], name: "index_teams_on_tournament_id"
  end

  create_table "tournament_prediction_scores", force: :cascade do |t|
    t.datetime "computed_at", null: false
    t.datetime "created_at", null: false
    t.integer "points_champion", default: 0, null: false
    t.integer "points_fourth", default: 0, null: false
    t.integer "points_runner_up", default: 0, null: false
    t.integer "points_third", default: 0, null: false
    t.integer "points_top_scorer", default: 0, null: false
    t.integer "total_points", default: 0, null: false
    t.bigint "tournament_prediction_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tournament_prediction_id"], name: "index_tournament_prediction_scores_on_tournament_prediction_id", unique: true
  end

  create_table "tournament_predictions", force: :cascade do |t|
    t.bigint "champion_id"
    t.datetime "created_at", null: false
    t.bigint "fourth_place_id"
    t.datetime "locked_at"
    t.bigint "runner_up_id"
    t.bigint "third_place_id"
    t.bigint "top_scorer_id"
    t.bigint "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["champion_id"], name: "index_tournament_predictions_on_champion_id"
    t.index ["fourth_place_id"], name: "index_tournament_predictions_on_fourth_place_id"
    t.index ["runner_up_id"], name: "index_tournament_predictions_on_runner_up_id"
    t.index ["third_place_id"], name: "index_tournament_predictions_on_third_place_id"
    t.index ["top_scorer_id"], name: "index_tournament_predictions_on_top_scorer_id"
    t.index ["tournament_id"], name: "index_tournament_predictions_on_tournament_id"
    t.index ["user_id", "tournament_id"], name: "index_tournament_predictions_on_user_id_and_tournament_id", unique: true
  end

  create_table "tournaments", force: :cascade do |t|
    t.bigint "champion_id"
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.bigint "fourth_place_id"
    t.string "name", null: false
    t.bigint "runner_up_id"
    t.datetime "starts_at", null: false
    t.bigint "third_place_id"
    t.bigint "top_scorer_id"
    t.datetime "updated_at", null: false
    t.index ["champion_id"], name: "index_tournaments_on_champion_id"
    t.index ["fourth_place_id"], name: "index_tournaments_on_fourth_place_id"
    t.index ["runner_up_id"], name: "index_tournaments_on_runner_up_id"
    t.index ["third_place_id"], name: "index_tournaments_on_third_place_id"
    t.index ["top_scorer_id"], name: "index_tournaments_on_top_scorer_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.string "avatar_url"
    t.datetime "banned_at"
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.boolean "system", default: false, null: false
    t.string "timezone", default: "UTC", null: false
    t.string "uid"
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "(provider IS NOT NULL)"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.text "object_changes"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "group_memberships", "groups"
  add_foreign_key "group_memberships", "users"
  add_foreign_key "groups", "users", column: "owner_id"
  add_foreign_key "matches", "matches", column: "feeds_into_match_id"
  add_foreign_key "matches", "teams", column: "advancing_team_id"
  add_foreign_key "matches", "teams", column: "away_team_id"
  add_foreign_key "matches", "teams", column: "home_team_id"
  add_foreign_key "matches", "tournaments"
  add_foreign_key "players", "teams"
  add_foreign_key "prediction_scores", "predictions"
  add_foreign_key "predictions", "matches"
  add_foreign_key "predictions", "teams", column: "predicted_advancing_team_id"
  add_foreign_key "predictions", "users"
  add_foreign_key "ranking_snapshots", "groups"
  add_foreign_key "ranking_snapshots", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "teams", "tournaments"
  add_foreign_key "tournament_prediction_scores", "tournament_predictions"
  add_foreign_key "tournament_predictions", "players", column: "top_scorer_id"
  add_foreign_key "tournament_predictions", "teams", column: "champion_id"
  add_foreign_key "tournament_predictions", "teams", column: "fourth_place_id"
  add_foreign_key "tournament_predictions", "teams", column: "runner_up_id"
  add_foreign_key "tournament_predictions", "teams", column: "third_place_id"
  add_foreign_key "tournament_predictions", "tournaments"
  add_foreign_key "tournament_predictions", "users"
  add_foreign_key "tournaments", "players", column: "top_scorer_id"
  add_foreign_key "tournaments", "teams", column: "champion_id"
  add_foreign_key "tournaments", "teams", column: "fourth_place_id"
  add_foreign_key "tournaments", "teams", column: "runner_up_id"
  add_foreign_key "tournaments", "teams", column: "third_place_id"
end
