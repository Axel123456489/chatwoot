# 🚀 Plan de Implementación: Workflow Integrations Architecture

## 📊 Estado Actual

### Tablas Existentes
```ruby
agent_bots:
  - id
  - name, description
  - outgoing_url
  - bot_type (enum: webhook)
  - bot_config (JSONB) ← Aquí está toda la config de n8n
  - account_id

n8n_flows:
  - id
  - conversation_id (unique)
  - flow_id
  - last_message_id
  - flow_webhook_url
  - last_triggered_at
```

### Problemas Identificados
1. ❌ Config sin estructura en JSONB
2. ❌ No extensible para otras integraciones
3. ❌ Estado del flujo mezclado con datos de ejecución
4. ❌ No hay historial de ejecuciones
5. ❌ Lógica compleja en N8nIntegration (503 líneas)

---

## 🎯 Nueva Arquitectura

### Diagrama de Entidades

```
┌──────────────────────────────────────────────────────────────┐
│                        AgentBot                               │
│  - Configuración básica del bot                              │
│  - Ya no usa bot_config para workflow-specific config        │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     │ has_one (polymorphic)
                     ▼
┌──────────────────────────────────────────────────────────────┐
│               WorkflowIntegration (STI)                       │
│  - type: 'WorkflowIntegrations::N8n'                         │
│  - agent_bot_id                                              │
│  - webhook_url                                               │
│  - config (JSONB estructurado por tipo)                     │
│  - enabled                                                   │
│  - status (active, paused, error)                           │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     │ has_many
                     ▼
┌──────────────────────────────────────────────────────────────┐
│               WorkflowExecution                               │
│  - workflow_integration_id                                   │
│  - conversation_id                                           │
│  - execution_id (flow_id externo)                           │
│  - webhook_url                                              │
│  - status (pending, running, completed, failed, cancelled)  │
│  - started_at, completed_at                                 │
│  - last_activity_at                                         │
│  - last_message_id                                          │
│  - trigger_type (new_conversation, reopen, manual, etc)    │
│  - metadata (JSONB)                                         │
│  - error_message                                            │
└──────────────────────────────────────────────────────────────┘
```

### Jerarquía de Clases STI

```ruby
WorkflowIntegration (base)
├── WorkflowIntegrations::N8n
├── WorkflowIntegrations::Make (futuro)
├── WorkflowIntegrations::Zapier (futuro)
└── WorkflowIntegrations::Custom (futuro)
```

---

## 📝 Plan de Implementación (5 Fases)

### 🔵 Fase 1: Migraciones y Modelos Base (Día 1)

#### 1.1 Crear tabla workflow_integrations

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_workflow_integrations.rb
class CreateWorkflowIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_integrations do |t|
      t.string :type, null: false  # STI
      t.references :agent_bot, null: false, foreign_key: true
      t.string :webhook_url, null: false
      t.jsonb :config, default: {}, null: false
      t.boolean :enabled, default: true, null: false
      t.string :status, default: 'active', null: false
      t.string :version, default: '1.0'
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :workflow_integrations, :type
    add_index :workflow_integrations, :status
    add_index :workflow_integrations, [:agent_bot_id, :type], unique: true
  end
end
```

#### 1.2 Crear tabla workflow_executions

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_workflow_executions.rb
class CreateWorkflowExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_executions do |t|
      t.references :workflow_integration, null: false, foreign_key: true, index: true
      t.references :conversation, null: false, foreign_key: true
      t.string :execution_id  # ID externo del workflow (flow_id)
      t.string :webhook_url
      t.string :status, default: 'pending', null: false
      t.string :trigger_type  # new_conversation, reopen, manual_pending, etc
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :last_activity_at
      t.bigint :last_message_id
      t.jsonb :metadata, default: {}
      t.text :error_message
      t.timestamps
    end

    add_index :workflow_executions, :execution_id
    add_index :workflow_executions, :status
    add_index :workflow_executions, [:conversation_id, :status]
    add_index :workflow_executions, :last_activity_at
    
    # Solo una ejecución activa por conversación
    add_index :workflow_executions, :conversation_id, 
              unique: true, 
              where: "status IN ('pending', 'running')",
              name: 'index_workflow_executions_unique_active_per_conversation'
  end
end
```

#### 1.3 Modelo Base: WorkflowIntegration

```ruby
# app/models/workflow_integration.rb
class WorkflowIntegration < ApplicationRecord
  belongs_to :agent_bot
  has_many :workflow_executions, dependent: :destroy
  
  validates :type, presence: true
  validates :webhook_url, presence: true, length: { maximum: Limits::URL_LENGTH_LIMIT }
  validates :webhook_url, format: URI::DEFAULT_PARSER.make_regexp(%w[http https])
  validates :status, inclusion: { in: %w[active paused error] }
  
  enum status: { active: 'active', paused: 'paused', error: 'error' }, _suffix: true
  
  # STI - Cada subclase implementa estos métodos
  def start_execution(conversation:, trigger_type:, payload:)
    raise NotImplementedError, "#{self.class} must implement #start_execution"
  end
  
  def forward_message(execution:, payload:)
    raise NotImplementedError, "#{self.class} must implement #forward_message"
  end
  
  def cancel_execution(execution:, reason: nil)
    raise NotImplementedError, "#{self.class} must implement #cancel_execution"
  end
  
  # Helpers compartidos
  def active_execution_for(conversation)
    workflow_executions
      .where(conversation: conversation)
      .where(status: %w[pending running])
      .order(started_at: :desc)
      .first
  end
  
  def can_start_execution?(conversation)
    enabled? && active_status? && !active_execution_for(conversation)
  end
  
  # Config helpers - cada subclase define sus propios accessors
  def config_value(key, default: nil)
    config.fetch(key.to_s, default)
  end
  
  def update_config(key, value)
    config[key.to_s] = value
    save!
  end
end
```

#### 1.4 Modelo: WorkflowExecution

```ruby
# app/models/workflow_execution.rb
class WorkflowExecution < ApplicationRecord
  belongs_to :workflow_integration
  belongs_to :conversation
  belongs_to :last_message, class_name: 'Message', optional: true
  
  validates :status, presence: true, inclusion: { 
    in: %w[pending running completed failed cancelled timeout] 
  }
  validates :trigger_type, presence: true, inclusion: {
    in: %w[new_conversation reopen manual_pending contact_pending webwidget]
  }
  
  enum status: {
    pending: 'pending',
    running: 'running',
    completed: 'completed',
    failed: 'failed',
    cancelled: 'cancelled',
    timeout: 'timeout'
  }, _suffix: true
  
  scope :active, -> { where(status: %w[pending running]) }
  scope :recent, -> { order(started_at: :desc) }
  scope :stale, ->(seconds = 3600) { 
    where('last_activity_at < ?', seconds.seconds.ago)
      .where(status: %w[pending running])
  }
  
  # Lifecycle methods
  def start!(execution_id:, webhook_url: nil)
    update!(
      status: 'running',
      execution_id: execution_id,
      webhook_url: webhook_url || self.webhook_url,
      started_at: Time.current,
      last_activity_at: Time.current
    )
  end
  
  def mark_activity!(message_id: nil)
    attrs = { last_activity_at: Time.current }
    attrs[:last_message_id] = message_id if message_id
    update!(attrs)
  end
  
  def complete!(metadata: {})
    update!(
      status: 'completed',
      completed_at: Time.current,
      metadata: self.metadata.merge(metadata)
    )
  end
  
  def fail!(error_message:, metadata: {})
    update!(
      status: 'failed',
      error_message: error_message,
      completed_at: Time.current,
      metadata: self.metadata.merge(metadata)
    )
  end
  
  def cancel!(reason: nil)
    update!(
      status: 'cancelled',
      completed_at: Time.current,
      error_message: reason
    )
  end
  
  def active?
    pending_status? || running_status?
  end
  
  def duration
    return nil unless started_at
    end_time = completed_at || Time.current
    end_time - started_at
  end
end
```

---

### 🟢 Fase 2: Implementación N8n Específica (Día 2)

#### 2.1 WorkflowIntegrations::N8n

```ruby
# app/models/workflow_integrations/n8n.rb
class WorkflowIntegrations::N8n < WorkflowIntegration
  # Config structure for n8n
  store_accessor :config,
    :start_on_new_conversation,
    :start_on_reopen,
    :start_on_manual_pending,
    :start_on_contact_pending,
    :triggers_version
  
  validates :start_on_new_conversation, inclusion: { in: [true, false] }
  validates :start_on_reopen, inclusion: { in: [true, false] }
  
  after_initialize :set_defaults, if: :new_record?
  
  def start_execution(conversation:, trigger_type:, payload:)
    return unless can_start_execution?(conversation)
    return unless should_start_for_trigger?(trigger_type)
    
    execution = workflow_executions.create!(
      conversation: conversation,
      trigger_type: trigger_type,
      webhook_url: webhook_url,
      status: 'pending',
      metadata: { payload_keys: payload.keys }
    )
    
    response = post_to_webhook(webhook_url, payload)
    flow_id = extract_flow_id(response)
    
    execution.start!(execution_id: flow_id, webhook_url: webhook_url)
    assign_bot_to_conversation(conversation)
    
    execution
  rescue StandardError => e
    execution&.fail!(error_message: "Failed to start: #{e.message}")
    Rails.logger.error("[N8n] Start execution failed: #{e.class} #{e.message}")
    raise
  end
  
  def forward_message(execution:, payload:)
    return unless execution.active?
    
    waiting_url = build_waiting_url(execution)
    return unless waiting_url
    
    post_to_webhook(waiting_url, payload)
    execution.mark_activity!(message_id: payload.dig(:message, :id))
  rescue StandardError => e
    Rails.logger.error("[N8n] Forward failed: #{e.class} #{e.message}")
    # No marcamos como failed, el flujo puede seguir corriendo
  end
  
  def cancel_execution(execution:, reason: nil)
    execution.cancel!(reason: reason)
    clear_bot_assignment(execution.conversation)
  end
  
  # N8n-specific helpers
  def should_start_for_trigger?(trigger_type)
    case trigger_type.to_sym
    when :new_conversation
      typed_config_value(:start_on_new_conversation, default: true)
    when :reopen
      typed_config_value(:start_on_reopen, default: true)
    when :manual_pending
      typed_config_value(:start_on_manual_pending, default: true)
    when :contact_pending
      typed_config_value(:start_on_contact_pending, default: false)
    else
      false
    end
  end
  
  private
  
  def set_defaults
    self.config ||= {}
    self.start_on_new_conversation = true if start_on_new_conversation.nil?
    self.start_on_reopen = true if start_on_reopen.nil?
    self.start_on_manual_pending = true if start_on_manual_pending.nil?
    self.start_on_contact_pending = false if start_on_contact_pending.nil?
    self.triggers_version = 2
  end
  
  def typed_config_value(key, default: nil)
    val = config_value(key, default: default)
    ActiveRecord::Type::Boolean.new.cast(val)
  end
  
  def build_waiting_url(execution)
    return nil if execution.webhook_url.blank? || execution.execution_id.blank?
    
    uri = URI.parse(execution.webhook_url)
    path = uri.path || ''
    prefix = path.include?('/webhook/') ? path.split('/webhook/').first : path.gsub(%r{/+$}, '')
    
    port_part = standard_port?(uri) ? '' : ":#{uri.port}"
    base = "#{uri.scheme}://#{uri.host}#{port_part}#{prefix}".gsub(%r{/+$}, '')
    
    "#{base}/webhook-waiting/#{execution.execution_id}"
  rescue URI::InvalidURIError => e
    Rails.logger.error("[N8n] Invalid webhook URL: #{e.message}")
    nil
  end
  
  def standard_port?(uri)
    (uri.scheme == 'https' && uri.port == 443) || (uri.scheme == 'http' && uri.port == 80)
  end
  
  def extract_flow_id(response)
    body = response.respond_to?(:parsed_response) ? response.parsed_response : {}
    body.is_a?(Hash) ? body['id'] : nil || "execution-#{Time.now.to_i}"
  end
  
  def post_to_webhook(url, payload)
    WorkflowIntegrations::WebhookPoster.new(url, payload).execute
  end
  
  def assign_bot_to_conversation(conversation)
    return if agent_bot.blank?
    return if conversation.assignee_agent_bot_id == agent_bot.id
    return if conversation.assignee_id.present?
    
    conversation.update!(assignee_agent_bot: agent_bot, assignee: nil)
  end
  
  def clear_bot_assignment(conversation)
    return if agent_bot.blank?
    return unless conversation.assignee_agent_bot_id == agent_bot.id
    
    AgentBots::ClearAssignmentJob.perform_later(conversation.id, agent_bot.id)
  end
end
```

---

### 🟡 Fase 3: Services y Concerns (Día 3)

#### 3.1 WebhookPoster (Reutilizable)

```ruby
# app/services/workflow_integrations/webhook_poster.rb
module WorkflowIntegrations
  class WebhookPoster
    MAX_RETRIES = 3
    BASE_BACKOFF = 0.25
    TIMEOUT = 8
    
    attr_reader :url, :payload
    
    def initialize(url, payload)
      @url = url
      @payload = payload
    end
    
    def execute
      attempts = 0
      
      begin
        started_at = Time.current
        response = http_post
        duration_ms = ((Time.current - started_at) * 1000).round
        
        if success?(response)
          log_success(response.code, duration_ms)
          return response
        end
        
        if retryable?(response)
          raise RetryableError, "HTTP #{response.code}"
        else
          raise NonRetryableError, "HTTP #{response.code}"
        end
      rescue RetryableError => e
        attempts += 1
        if attempts < MAX_RETRIES
          sleep_time = backoff_with_jitter(attempts)
          log_retry(attempts, sleep_time, e.message)
          sleep(sleep_time)
          retry
        end
        log_error(attempts, e.message)
        raise
      rescue StandardError => e
        log_error(attempts, e.message)
        raise
      end
    end
    
    private
    
    def http_post
      HTTParty.post(url, {
        headers: { 'Content-Type' => 'application/json' },
        body: payload.to_json,
        timeout: TIMEOUT
      })
    end
    
    def success?(response)
      response.code.between?(200, 299)
    end
    
    def retryable?(response)
      code = response.code.to_i
      return true if code.zero?
      return true if [408, 429].include?(code)
      return true if code.between?(500, 599)
      false
    end
    
    def backoff_with_jitter(attempt)
      base = BASE_BACKOFF * (2 ** (attempt - 1))
      jitter = rand(0.0..(base / 2.0))
      (base + jitter).round(3)
    end
    
    def safe_url
      uri = URI.parse(url)
      port_part = standard_port?(uri) ? '' : ":#{uri.port}"
      "#{uri.scheme}://#{uri.host}#{port_part}#{uri.path}"
    rescue URI::InvalidURIError
      '<invalid-url>'
    end
    
    def standard_port?(uri)
      (uri.scheme == 'https' && uri.port == 443) || (uri.scheme == 'http' && uri.port == 80)
    end
    
    def log_success(code, duration_ms)
      Rails.logger.info("[WebhookPoster] Success url=#{safe_url} code=#{code} dur_ms=#{duration_ms}")
    end
    
    def log_retry(attempt, sleep_time, error)
      Rails.logger.info("[WebhookPoster] Retry attempt=#{attempt} sleep=#{sleep_time}s url=#{safe_url} error=#{error}")
    end
    
    def log_error(attempts, error)
      Rails.logger.error("[WebhookPoster] Failed attempts=#{attempts} url=#{safe_url} error=#{error}")
    end
    
    class RetryableError < StandardError; end
    class NonRetryableError < StandardError; end
  end
end
```

#### 3.2 TriggerDetector

```ruby
# app/services/workflow_integrations/trigger_detector.rb
module WorkflowIntegrations
  class TriggerDetector
    attr_reader :conversation, :message, :event
    
    def initialize(conversation:, message: nil, event: nil)
      @conversation = conversation
      @message = message
      @event = event
    end
    
    def detect_trigger_type
      return :reopen if message_reopened_conversation?
      return :new_conversation if new_conversation?
      return :manual_pending if manual_pending_change?
      return :contact_pending if contact_pending_change?
      :existing
    end
    
    private
    
    def message_reopened_conversation?
      return false unless event&.data
      event.data[:reopened_conversation] == true || event.data['reopened_conversation'] == true
    end
    
    def new_conversation?
      return false unless message
      !conversation.messages.incoming.where.not(id: message.id).exists?
    end
    
    def manual_pending_change?
      return false unless status_changed_to_pending?
      actor = event&.data&.dig(:performed_by) || event&.data&.dig('performed_by')
      actor.is_a?(User)
    end
    
    def contact_pending_change?
      return false unless status_changed_to_pending?
      actor = event&.data&.dig(:performed_by) || event&.data&.dig('performed_by')
      actor.is_a?(Contact)
    end
    
    def status_changed_to_pending?
      return false unless event&.data
      changed = event.data[:changed_attributes] || event.data['changed_attributes']
      return false unless changed
      
      status_change = changed['status'] || changed[:status]
      return false unless status_change
      
      status_change.last&.to_s == 'pending'
    end
  end
end
```

#### 3.3 Executor (Orquestador principal)

```ruby
# app/services/workflow_integrations/executor.rb
module WorkflowIntegrations
  class Executor
    attr_reader :integration, :conversation, :event
    
    def initialize(integration:, conversation:, event: nil)
      @integration = integration
      @conversation = conversation
      @event = event
    end
    
    def handle_message(message)
      trigger_type = detect_trigger(message)
      
      if should_start_new_execution?(trigger_type)
        start_execution(message, trigger_type)
      elsif should_forward_message?
        forward_message(message)
      end
    end
    
    def handle_status_change
      if exiting_from_pending?
        cancel_active_execution
      elsif entering_pending?
        trigger_type = detect_trigger(nil)
        start_execution(nil, trigger_type) if should_start_new_execution?(trigger_type)
      end
    end
    
    private
    
    def detect_trigger(message)
      TriggerDetector.new(
        conversation: conversation,
        message: message,
        event: event
      ).detect_trigger_type
    end
    
    def should_start_new_execution?(trigger_type)
      return false if trigger_type == :existing
      return false if active_execution
      return false if recently_started?
      
      integration.should_start_for_trigger?(trigger_type)
    end
    
    def should_forward_message?
      active_execution.present? && conversation.pending?
    end
    
    def start_execution(message, trigger_type)
      ensure_pending_status unless conversation.pending?
      
      payload = build_payload(message)
      integration.start_execution(
        conversation: conversation,
        trigger_type: trigger_type,
        payload: payload
      )
    rescue StandardError => e
      Rails.logger.error("[Executor] Start execution failed: #{e.class} #{e.message}")
    end
    
    def forward_message(message)
      payload = build_payload(message)
      integration.forward_message(execution: active_execution, payload: payload)
    rescue StandardError => e
      Rails.logger.error("[Executor] Forward message failed: #{e.class} #{e.message}")
    end
    
    def cancel_active_execution
      return unless active_execution
      integration.cancel_execution(execution: active_execution, reason: 'Status change')
    end
    
    def active_execution
      @active_execution ||= integration.active_execution_for(conversation)
    end
    
    def recently_started?
      return false unless active_execution
      active_execution.started_at && active_execution.started_at > 10.seconds.ago
    end
    
    def exiting_from_pending?
      conversation.status_previously_changed? &&
        conversation.status_previous_change&.first == 'pending'
    end
    
    def entering_pending?
      conversation.status_previously_changed? &&
        conversation.status_previous_change&.last == 'pending'
    end
    
    def ensure_pending_status
      with_bot_as_executor { conversation.pending! }
    rescue StandardError => e
      Rails.logger.warn("[Executor] Failed to set pending: #{e.message}")
    end
    
    def with_bot_as_executor
      previous = Current.executed_by
      Current.executed_by = integration.agent_bot
      yield
    ensure
      Current.executed_by = previous
    end
    
    def build_payload(message)
      WorkflowIntegrations::PayloadBuilder.new(
        conversation: conversation,
        message: message,
        event: event
      ).build
    end
  end
end
```

---

### 🟣 Fase 4: Migración de Datos y Actualización Listeners (Día 4)

#### 4.1 Migración de Datos de N8nFlow a WorkflowExecution

```ruby
# db/migrate/YYYYMMDDHHMMSS_migrate_n8n_flows_to_workflow_integrations.rb
class MigrateN8nFlowsToWorkflowIntegrations < ActiveRecord::Migration[7.1]
  def up
    say "Migrando AgentBots con n8n_native a WorkflowIntegrations..."
    
    AgentBot.where("bot_config->>'n8n_native' = 'true'").find_each do |agent_bot|
      next if WorkflowIntegration.exists?(agent_bot: agent_bot, type: 'WorkflowIntegrations::N8n')
      
      config = extract_n8n_config(agent_bot.bot_config)
      
      workflow_integration = WorkflowIntegrations::N8n.create!(
        agent_bot: agent_bot,
        webhook_url: agent_bot.outgoing_url,
        config: config,
        enabled: true,
        status: 'active'
      )
      
      say "  ✓ Created WorkflowIntegration for AgentBot ##{agent_bot.id}"
      
      # Migrar n8n_flows activos a workflow_executions
      migrate_active_flows(workflow_integration)
    end
    
    say "Migración completada!"
  end
  
  def down
    say "Rollback: eliminando WorkflowIntegrations de tipo N8n"
    WorkflowIntegrations::N8n.destroy_all
  end
  
  private
  
  def extract_n8n_config(bot_config)
    {
      'start_on_new_conversation' => bot_config['n8n_start_on_message'],
      'start_on_reopen' => bot_config['n8n_start_on_reopen'] || bot_config['n8n_restart_on_reopen'],
      'start_on_manual_pending' => bot_config['n8n_start_on_manual_pending'],
      'start_on_contact_pending' => bot_config['n8n_start_on_contact_pending'],
      'triggers_version' => bot_config['n8n_triggers_version'] || 2
    }
  end
  
  def migrate_active_flows(workflow_integration)
    agent_bot = workflow_integration.agent_bot
    
    # Encontrar conversaciones asignadas a este bot con n8n_flow activo
    Conversation.where(assignee_agent_bot: agent_bot).includes(:n8n_flow).find_each do |conversation|
      next unless conversation.n8n_flow&.active?
      
      flow = conversation.n8n_flow
      
      WorkflowExecution.create!(
        workflow_integration: workflow_integration,
        conversation: conversation,
        execution_id: flow.flow_id,
        webhook_url: flow.flow_webhook_url,
        status: 'running',
        trigger_type: 'new_conversation', # Default, no sabemos el real
        started_at: flow.last_triggered_at || flow.created_at,
        last_activity_at: flow.last_triggered_at || flow.updated_at,
        last_message_id: flow.last_message_id,
        metadata: { migrated_from_n8n_flow: true }
      )
      
      say "  ✓ Migrated active flow for Conversation ##{conversation.id}"
    rescue StandardError => e
      say "  ✗ Failed to migrate flow for Conversation ##{conversation.id}: #{e.message}", :red
    end
  end
end
```

#### 4.2 Actualizar AgentBotListener

```ruby
# app/listeners/agent_bot_listener.rb
class AgentBotListener < BaseListener
  def conversation_updated(event)
    conversation = extract_conversation_and_account(event)[0]
    inbox = conversation.inbox
    
    workflow_integrations_for(inbox, conversation).each do |integration|
      executor = WorkflowIntegrations::Executor.new(
        integration: integration,
        conversation: conversation,
        event: event
      )
      executor.handle_status_change
    end
    
    # Legacy webhook bots (non-workflow)
    legacy_agent_bots_for(inbox, conversation).each do |agent_bot|
      integration_for(agent_bot).conversation_updated(conversation, event)
    end
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox
    return unless message.webhook_sendable?
    
    conversation = message.conversation
    
    workflow_integrations_for(inbox, conversation).each do |integration|
      executor = WorkflowIntegrations::Executor.new(
        integration: integration,
        conversation: conversation,
        event: event
      )
      executor.handle_message(message)
    end
    
    # Legacy webhook bots (non-workflow)
    legacy_agent_bots_for(inbox, conversation).each do |agent_bot|
      integration_for(agent_bot).message_created(message, event)
    end
  end

  # ... otros métodos sin cambios

  private

  def workflow_integrations_for(inbox, conversation = nil)
    integrations = []
    
    # Workflow integration del bot asignado a la conversación
    if conversation&.assignee_agent_bot.present?
      bot_integration = conversation.assignee_agent_bot.workflow_integration
      integrations << bot_integration if bot_integration&.enabled?
    end
    
    # Workflow integration del bot del inbox
    inbox_bot = active_inbox_agent_bot(inbox)
    if inbox_bot.present?
      inbox_integration = inbox_bot.workflow_integration
      integrations << inbox_integration if inbox_integration&.enabled?
    end
    
    integrations.compact.uniq
  end
  
  def legacy_agent_bots_for(inbox, conversation = nil)
    bots = []
    
    # Bots que NO tienen workflow_integration (webhooks legacy)
    if conversation&.assignee_agent_bot.present? && conversation.assignee_agent_bot.workflow_integration.nil?
      bots << conversation.assignee_agent_bot
    end
    
    inbox_bot = active_inbox_agent_bot(inbox)
    if inbox_bot.present? && inbox_bot.workflow_integration.nil?
      bots << inbox_bot
    end
    
    bots.compact.uniq
  end
  
  def active_inbox_agent_bot(inbox)
    return unless inbox.agent_bot_inbox&.active?
    inbox.agent_bot
  end
  
  def integration_for(agent_bot)
    # Legacy webhook integration
    AgentBots::Integrations::WebhookIntegration.new(agent_bot)
  end
end
```

---

### 🔴 Fase 5: Controllers, Tests y Cleanup (Día 5)

#### 5.1 Actualizar Controlador

```ruby
# app/controllers/api/v1/integrations/workflows_controller.rb
class Api::V1::Integrations::WorkflowsController < ApplicationController
  before_action :find_conversation, only: [:switch_execution, :cancel_execution]
  
  # POST /api/v1/integrations/workflows/switch_execution
  def switch_execution
    integration = WorkflowIntegration.find_by!(id: params[:integration_id])
    
    # Cancelar ejecución activa si existe
    active = integration.active_execution_for(@conversation)
    active&.cancel!(reason: 'Switched to new flow')
    
    # Crear nueva ejecución
    execution = integration.workflow_executions.create!(
      conversation: @conversation,
      execution_id: params[:execution_id],
      webhook_url: params[:webhook_url] || integration.webhook_url,
      status: 'running',
      trigger_type: 'manual',
      started_at: Time.current,
      last_activity_at: Time.current
    )
    
    render json: {
      message: 'Execution switched successfully',
      execution: execution_json(execution)
    }, status: :ok
  rescue StandardError => e
    Rails.logger.error("[Workflows] Switch failed: #{e.class} #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end
  
  # POST /api/v1/integrations/workflows/:id/cancel
  def cancel_execution
    execution = WorkflowExecution.find(params[:id])
    execution.cancel!(reason: params[:reason] || 'Manual cancellation')
    
    render json: {
      message: 'Execution cancelled',
      execution: execution_json(execution)
    }, status: :ok
  end
  
  # GET /api/v1/integrations/workflows/executions/:conversation_id
  def executions
    conversation = Conversation.find(params[:conversation_id])
    executions = WorkflowExecution
                   .where(conversation: conversation)
                   .recent
                   .limit(20)
    
    render json: {
      executions: executions.map { |e| execution_json(e) }
    }, status: :ok
  end
  
  private
  
  def find_conversation
    @conversation = Conversation.find(params[:conversation_id])
  end
  
  def execution_json(execution)
    {
      id: execution.id,
      execution_id: execution.execution_id,
      status: execution.status,
      trigger_type: execution.trigger_type,
      started_at: execution.started_at,
      completed_at: execution.completed_at,
      duration: execution.duration,
      conversation_id: execution.conversation_id,
      integration_type: execution.workflow_integration.type
    }
  end
end
```

#### 5.2 Actualizar Routes

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    namespace :integrations do
      # New workflow endpoints
      resources :workflows, only: [] do
        collection do
          post :switch_execution
          get 'executions/:conversation_id', action: :executions
        end
        member do
          post :cancel
        end
      end
      
      # Deprecated: mantener por backward compatibility
      post 'n8n/switch_flow', to: 'n8n#switch_flow' # Redirect a workflows
    end
  end
end
```

---

## 📊 Checklist de Implementación

### Día 1: Fundación
- [ ] Crear migración `create_workflow_integrations`
- [ ] Crear migración `create_workflow_executions`
- [ ] Crear modelo `WorkflowIntegration` base
- [ ] Crear modelo `WorkflowExecution`
- [ ] Correr migraciones
- [ ] Tests unitarios para modelos

### Día 2: N8n Específico
- [ ] Crear `WorkflowIntegrations::N8n`
- [ ] Implementar `start_execution`
- [ ] Implementar `forward_message`
- [ ] Implementar `cancel_execution`
- [ ] Tests para N8n integration

### Día 3: Services
- [ ] Crear `WebhookPoster`
- [ ] Crear `TriggerDetector`
- [ ] Crear `PayloadBuilder`
- [ ] Crear `Executor`
- [ ] Tests para services

### Día 4: Migración
- [ ] Crear migración de datos
- [ ] Actualizar `AgentBotListener`
- [ ] Actualizar `AgentBot` model (has_one :workflow_integration)
- [ ] Tests de integración

### Día 5: Controllers y Cleanup
- [ ] Crear `WorkflowsController`
- [ ] Actualizar routes
- [ ] Deprecar endpoints viejos
- [ ] Tests E2E
- [ ] Documentación

### Post-Deploy
- [ ] Monitoreo en producción
- [ ] Cleanup de código legacy (después de 2 semanas)
- [ ] Remover tabla `n8n_flows` (después de 1 mes)

---

## 🎯 Beneficios de la Nueva Arquitectura

### ✅ Inmediatos
1. **Configuración estructurada** - Validación en models
2. **Estado claro** - WorkflowExecution tiene todo el estado
3. **Historial completo** - Todas las ejecuciones guardadas
4. **Debugging fácil** - Logs y metadata por ejecución
5. **Testing simple** - Dependencias claras

### 🚀 Futuro
1. **Extensible** - Agregar Make/Zapier = 1 subclase
2. **Analytics** - Métricas por tipo de workflow
3. **Retry logic** - Re-ejecutar workflows fallidos
4. **Dashboard** - Ver ejecuciones en UI
5. **Webhooks entrantes** - Callbacks de workflows

---

## 🔄 Plan de Rollback

Si algo sale mal:

1. **Día 1-2**: Simplemente drop las tablas nuevas
2. **Día 3-4**: Revertir migraciones, volver a código legacy
3. **Día 5**: Feature flag para cambiar entre old/new
4. **Post-deploy**: Los datos migraros están intactos, solo desactivar

---

## 📈 Métricas de Éxito

- ✅ 100% de n8n_flows migrados sin pérdida de datos
- ✅ 0 downtime durante migración
- ✅ Reducción de 60% en líneas de código
- ✅ Tiempo de respuesta de workflows < 200ms
- ✅ 0 errores de trigger duplicados

---

**Última actualización**: 2026-02-19
**Estado**: Ready para implementación
**Estimación total**: 5 días de desarrollo + 2 días de testing
