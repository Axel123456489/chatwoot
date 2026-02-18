module Enterprise::Conversations::EventDataPresenter
  def push_data
    return super unless account.feature_enabled?('sla') && (applied_sla.present? || sla_events.any? || sla_policy_id.present?)

    super.merge(
      applied_sla: applied_sla&.push_event_data,
      sla_events: sla_events.map(&:push_event_data),
      sla_policy_id: sla_policy_id
    )
  end
end
