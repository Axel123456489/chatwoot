# frozen_string_literal: true

class AddConfigFieldsToWahaSessions < ActiveRecord::Migration[7.0]
  def change
    return unless table_exists?(:waha_sessions)

    add_column :waha_sessions, :debug, :boolean, default: false
    add_column :waha_sessions, :metadata, :jsonb, default: {}
    add_column :waha_sessions, :ignore_groups, :boolean, default: false
    add_column :waha_sessions, :ignore_channels, :boolean, default: true
    add_column :waha_sessions, :ignore_status, :boolean, default: true
    add_column :waha_sessions, :ignore_broadcast, :boolean, default: true
    add_column :waha_sessions, :proxy_server, :string
    add_column :waha_sessions, :proxy_username, :string
    add_column :waha_sessions, :proxy_password, :string
    add_column :waha_sessions, :noweb_store_enabled, :boolean, default: true
    add_column :waha_sessions, :noweb_store_full_sync, :boolean, default: false
  end
end
