# frozen_string_literal: true

# == Schema Information
#
# Table name: whatsapp_calls
#
#  id                   :bigint           not null, primary key
#  accepted_at          :datetime
#  browser_sdp_offer    :text
#  call_quality_metrics :jsonb
#  connected_at         :datetime
#  direction            :string(20)       not null
#  duration_seconds     :integer
#  ended_at             :datetime
#  initiated_at         :datetime
#  metadata             :jsonb
#  recording_enabled    :boolean          default(FALSE)
#  recording_url        :string
#  rejection_reason     :string
#  ringing_at           :datetime
#  status               :string(30)       default("initiated"), not null
#  status_reason        :string(100)
#  whatsapp_sdp_answer  :text
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  accepted_by_user_id  :bigint
#  account_id           :bigint           not null
#  call_id              :string           not null
#  contact_id           :bigint           not null
#  conversation_id      :bigint           not null
#  inbox_id             :bigint           not null
#  initiated_by_user_id :bigint
#
# Indexes
#
#  index_whatsapp_calls_on_accepted_by_user_id                 (accepted_by_user_id)
#  index_whatsapp_calls_on_account_id                          (account_id)
#  index_whatsapp_calls_on_account_id_and_status               (account_id,status)
#  index_whatsapp_calls_on_call_id                             (call_id) UNIQUE
#  index_whatsapp_calls_on_contact_id                          (contact_id)
#  index_whatsapp_calls_on_contact_id_and_created_at           (contact_id,created_at)
#  index_whatsapp_calls_on_conversation_id                     (conversation_id)
#  index_whatsapp_calls_on_conversation_id_and_created_at      (conversation_id,created_at)
#  index_whatsapp_calls_on_inbox_id                            (inbox_id)
#  index_whatsapp_calls_on_inbox_id_and_created_at_and_status  (inbox_id,created_at,status)
#  index_whatsapp_calls_on_initiated_by_user_id                (initiated_by_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (accepted_by_user_id => users.id)
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (initiated_by_user_id => users.id)
#
# Model for WhatsApp calls with State Machine
class WhatsappCall < ApplicationRecord
  include AASM

  # Associations
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact
  belongs_to :inbox
  belongs_to :initiated_by_user, class_name: 'User', optional: true
  belongs_to :accepted_by_user, class_name: 'User', optional: true

  # Validations
  validates :call_id, presence: true, uniqueness: { case_sensitive: true }
  validates :direction, presence: true, inclusion: { in: %w[outbound inbound unknown] }
  validates :account, presence: true
  validates :conversation, presence: true
  validates :contact, presence: true
  validates :inbox, presence: true
  validates :duration_seconds, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Callbacks
  before_validation :set_default_values, on: :create
  after_create :broadcast_call_created

  # Virtual accessors backed by metadata to align with WhatsApp payload fields
  store_accessor :metadata,
                 :whatsapp_call_sid,
                 :from_number,
                 :to_number,
                 :call_duration,
                 :recording_url,
                 :recording_duration,
                 :error_code,
                 :error_message,
                 :call_status_reason

  # Backward-compatible attribute names used across the codebase and specs
  alias_attribute :call_direction, :direction
  alias_attribute :call_status, :status

  STATUS_ALIASES = {
    'completed' => 'ended',
    'missed' => 'timeout',
    'busy' => 'failed',
    'no_connection' => 'failed'
  }.freeze

  # Enums
  enum direction: {
    outbound: 'outbound',
    inbound: 'inbound',
    unknown: 'unknown'
  }, _prefix: true

  # State Machine with AASM
  aasm column: :status do
    state :initiated, initial: true
    state :ringing, :accepted, :connecting, :connected
    state :holding, :ended, :failed, :rejected, :timeout, :cancelled

    event :ring do
      transitions from: :initiated, to: :ringing, after: :set_ringing_at
    end

    event :accept do
      transitions from: :ringing, to: :accepted, after: :set_accepted_at
    end

    event :start_connecting do
      transitions from: :accepted, to: :connecting
    end

    event :connect do
      transitions from: [:accepted, :connecting], to: :connected, after: :set_connected_at
    end

    event :hold do
      transitions from: :connected, to: :holding
    end

    event :resume do
      transitions from: :holding, to: :connected
    end

    event :end_call do
      transitions from: [:initiated, :ringing, :accepted, :connecting, :connected, :holding],
                  to: :ended,
                  after: :finalize_call
    end

    event :fail do
      transitions from: [:initiated, :ringing, :accepted, :connecting, :connected],
                  to: :failed,
                  after: :finalize_call
    end

    event :reject do
      transitions from: [:initiated, :ringing], to: :rejected, after: :finalize_call
    end

    event :timeout do
      transitions from: [:initiated, :ringing], to: :timeout, after: :finalize_call
    end

    event :cancel do
      transitions from: [:initiated, :ringing], to: :cancelled, after: :finalize_call
    end
  end

  # Scopes
  scope :active, -> { where(status: %w[initiated ringing accepted connecting connected holding]) }
  scope :ended, -> { where(status: %w[ended failed rejected timeout cancelled]) }
  scope :successful, -> { where(status: 'ended').where.not(duration_seconds: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }
  scope :with_associations, -> { includes(:account, :conversation, :contact, :inbox, :initiated_by_user) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :for_inbox, ->(inbox_id) { where(inbox_id: inbox_id) }
  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }
  scope :outbound, -> { where(direction: 'outbound') }
  scope :inbound, -> { where(direction: 'inbound') }

  # Instance methods
  def active?
    %w[initiated ringing accepted connecting connected holding].include?(status)
  end

  def ended?
    %w[ended failed rejected timeout cancelled].include?(status)
  end

  def successful?
    status == 'ended' && duration_seconds.present? && duration_seconds.positive?
  end

  def duration_formatted
    return nil unless duration_seconds

    minutes = duration_seconds / 60
    seconds = duration_seconds % 60

    if minutes.positive?
      "#{minutes}m #{seconds}s"
    else
      "#{seconds}s"
    end
  end

  def calculate_duration
    return unless connected_at && ended_at

    self.duration_seconds = (ended_at - connected_at).to_i
  end

  def call_direction=(value)
    direction_value = value.to_s
    if self.class.directions.key?(direction_value)
      super(direction_value)
    else
      self[:direction] = direction_value
    end
  end

  def call_status=(value)
    status_value = value.to_s
    self.call_status_reason = status_value if %w[busy no_connection failed].include?(status_value)
    normalized = STATUS_ALIASES[status_value] || status_value
    return unless self.class.aasm.states.map(&:name).map(&:to_s).include?(normalized)

    self[:status] = normalized
  end

  def call_status
    return 'missed' if status == 'timeout'
    return 'completed' if status == 'ended'
    return call_status_reason if status == 'failed' && call_status_reason.present?

    status
  end

  # Check if recording is enabled for this call
  # By default, all calls should be recorded
  def recording_enabled
    # You can add custom logic here to check account settings
    # For now, enable recording for all calls
    true
  end

  # Store call quality metrics (thread-safe)
  def record_quality_metric(metric_name, value)
    with_lock do
      self.call_quality_metrics ||= {}
      self.call_quality_metrics[metric_name] = value
      save!
    end
  end

  private

  # Validation callbacks
  def set_default_values
    self.contact ||= conversation&.contact
    self.inbox ||= conversation&.inbox
    self.initiated_at ||= Time.current
  end

  # Creation callbacks
  def broadcast_call_created
    conversation_attrs = conversation&.additional_attributes || {}
    sdp_offer = conversation_attrs['sdp_offer']
    from_number = conversation_attrs['from_number'] || conversation&.contact&.phone_number
    to_number = conversation_attrs['to_number']
    contact_name = conversation&.contact&.name

    ActionCable.server.broadcast(
      "account_#{account_id}",
      {
        event: 'whatsapp_call_created',
        data: {
          account_id: account_id,
          call_id: call_id,
          conversation_id: conversation.display_id,
          status: status,
          direction: direction,
          sdp_offer: sdp_offer,
          from_number: from_number,
          to_number: to_number,
          contact_name: contact_name
        }
      }
    )
  rescue StandardError => e
    Rails.logger.error "[WhatsappCall] Failed to broadcast call created: #{e.message}"
  end

  # AASM callbacks
  def set_ringing_at
    self.ringing_at = Time.current unless ringing_at
    broadcast_state_change
  end

  def set_accepted_at
    self.accepted_at = Time.current unless accepted_at
    broadcast_state_change
  end

  def set_connected_at
    self.connected_at = Time.current unless connected_at
    broadcast_state_change
  end

  def finalize_call
    self.ended_at = Time.current unless ended_at
    calculate_duration if connected_at
    broadcast_state_change
  end

  def broadcast_state_change
    data_payload = {
      account_id: account_id,  # Required for frontend isAValidEvent check
      call_id: call_id,
      conversation_id: conversation.display_id,
      status: status,
      duration: duration_formatted,
      metadata: {
        direction: direction,
        initiated_at: initiated_at,
        connected_at: connected_at,
        ended_at: ended_at
      }
    }

    Rails.logger.info "[WhatsappCall] Broadcasting state change: #{data_payload.inspect}"

    ActionCable.server.broadcast(
      "account_#{account_id}",
      {
        event: 'whatsapp_call_status_changed',
        data: data_payload
      }
    )
  rescue StandardError => e
    Rails.logger.error "[WhatsappCall] Failed to broadcast state change: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
