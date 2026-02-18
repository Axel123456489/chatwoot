class CleanupN8nFlows < ActiveRecord::Migration[7.0]
  def change
    remove_column :n8n_flows, :flow_status, :string, default: 'pending', null: false
    remove_column :n8n_flows, :reserving_flow, :boolean, default: false, null: false
  end
end
