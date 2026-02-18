class AddPerformanceIndexesToConversations < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    # Índice para el ordenamiento por defecto (last_activity_at DESC) con filtros comunes
    # Optimiza: conversaciones abiertas ordenadas por última actividad
    add_index :conversations,
              [:account_id, :status, :last_activity_at],
              name: 'index_conversations_on_account_status_last_activity',
              algorithm: :concurrently

    # Índice para conversaciones asignadas a un agente específico
    # Optimiza: vista "Mías" del agente
    add_index :conversations,
              [:assignee_id, :account_id, :status, :last_activity_at],
              name: 'index_conversations_on_assignee_account_status_activity',
              algorithm: :concurrently

    # Índice para conversaciones no asignadas
    # Optimiza: vista "No asignadas"
    add_index :conversations,
              [:account_id, :status, :last_activity_at],
              where: 'assignee_id IS NULL',
              name: 'index_conversations_on_unassigned_account_status_activity',
              algorithm: :concurrently

    # Índice para búsquedas por inbox
    # Optimiza: filtro por bandeja de entrada
    add_index :conversations,
              [:inbox_id, :status, :last_activity_at],
              name: 'index_conversations_on_inbox_status_activity',
              algorithm: :concurrently

    # Índice para búsquedas por equipo
    # Optimiza: filtro por equipo
    add_index :conversations,
              [:team_id, :status, :last_activity_at],
              where: 'team_id IS NOT NULL',
              name: 'index_conversations_on_team_status_activity',
              algorithm: :concurrently
  end
end
