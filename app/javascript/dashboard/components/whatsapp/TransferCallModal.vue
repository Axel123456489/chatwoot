<script>
import { mapGetters } from 'vuex';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Multiselect from 'vue-multiselect';

export default {
  name: 'TransferCallModal',
  components: {
    Avatar,
    Multiselect,
  },
  props: {
    call: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      transferType: 'agent',
      selectedAgentId: null,
      selectedInbox: null,
      searchQuery: '',
      transferNote: '',
    };
  },
  computed: {
    ...mapGetters({
      agents: 'agents/getAgents',
      inboxes: 'inboxes/getInboxes',
      currentUser: 'getCurrentUser',
    }),
    availableAgents() {
      return this.agents.filter(
        agent =>
          agent.id !== this.currentUser.id &&
          agent.availability_status !== 'offline'
      );
    },
    filteredAgents() {
      if (!this.searchQuery) {
        return this.availableAgents;
      }

      const query = this.searchQuery.toLowerCase();
      return this.availableAgents.filter(
        agent =>
          agent.name.toLowerCase().includes(query) ||
          agent.email.toLowerCase().includes(query)
      );
    },
    availableInboxes() {
      return this.inboxes.filter(
        inbox =>
          inbox.channel_type === 'Channel::Whatsapp' && inbox.calling_enabled
      );
    },
    canTransfer() {
      if (this.transferType === 'agent') {
        return this.selectedAgentId !== null;
      }
      return this.selectedInbox !== null;
    },
  },
  methods: {
    selectAgent(agentId) {
      this.selectedAgentId = agentId;
    },
    getStatusText(status) {
      const statusMap = {
        online: this.$t('WHATSAPP_CALLS.AGENT_STATUS.ONLINE'),
        busy: this.$t('WHATSAPP_CALLS.AGENT_STATUS.BUSY'),
        offline: this.$t('WHATSAPP_CALLS.AGENT_STATUS.OFFLINE'),
      };
      return statusMap[status] || status;
    },
    handleTransfer() {
      const transferData = {
        note: this.transferNote,
      };

      if (this.transferType === 'agent') {
        transferData.targetAgentId = this.selectedAgentId;
      } else {
        transferData.targetInboxId = this.selectedInbox.id;
      }

      this.$emit('transfer', transferData);
    },
  },
};
</script>

<template>
  <div class="transfer-call-modal">
    <woot-modal-header
      :header-title="$t('WHATSAPP_CALLS.TRANSFER_CALL')"
      :header-content="$t('WHATSAPP_CALLS.TRANSFER_CALL_DESCRIPTION')"
    />

    <div class="modal-content">
      <!-- Transfer Type Selection -->
      <div class="transfer-type-section">
        <label class="section-label">
          {{ $t('WHATSAPP_CALLS.TRANSFER_TYPE') }}
        </label>

        <div class="transfer-type-options">
          <woot-button
            :variant="transferType === 'agent' ? 'smooth' : 'clear'"
            @click="transferType = 'agent'"
          >
            <fluent-icon icon="person" size="16" />
            {{ $t('WHATSAPP_CALLS.TRANSFER_TO_AGENT') }}
          </woot-button>

          <woot-button
            :variant="transferType === 'inbox' ? 'smooth' : 'clear'"
            @click="transferType = 'inbox'"
          >
            <fluent-icon icon="mail-inbox" size="16" />
            {{ $t('WHATSAPP_CALLS.TRANSFER_TO_INBOX') }}
          </woot-button>
        </div>
      </div>

      <!-- Agent Selection -->
      <div v-if="transferType === 'agent'" class="selection-section">
        <label class="section-label">
          {{ $t('WHATSAPP_CALLS.SELECT_AGENT') }}
        </label>

        <div class="agent-search">
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="$t('WHATSAPP_CALLS.SEARCH_AGENTS')"
            class="search-input"
          />
        </div>

        <div class="agent-list">
          <div
            v-for="agent in filteredAgents"
            :key="agent.id"
            class="agent-item"
            :class="{ selected: selectedAgentId === agent.id }"
            @click="selectAgent(agent.id)"
          >
            <Avatar :src="agent.thumbnail" :name="agent.name" :size="32" />

            <div class="agent-info">
              <span class="agent-name">{{ agent.name }}</span>
              <span
                class="agent-status"
                :class="`status-${agent.availability_status}`"
              >
                {{ getStatusText(agent.availability_status) }}
              </span>
            </div>

            <fluent-icon
              v-if="selectedAgentId === agent.id"
              icon="checkmark-circle"
              size="20"
              class="selected-icon"
            />
          </div>

          <div v-if="filteredAgents.length === 0" class="empty-state">
            <p>{{ $t('WHATSAPP_CALLS.NO_AGENTS_FOUND') }}</p>
          </div>
        </div>
      </div>

      <!-- Inbox Selection -->
      <div v-if="transferType === 'inbox'" class="selection-section">
        <label class="section-label">
          {{ $t('WHATSAPP_CALLS.SELECT_INBOX') }}
        </label>

        <Multiselect
          v-model="selectedInbox"
          :options="availableInboxes"
          :placeholder="$t('WHATSAPP_CALLS.SELECT_INBOX_PLACEHOLDER')"
          label="name"
          track-by="id"
          :show-labels="false"
        />
      </div>

      <!-- Transfer Note -->
      <div class="note-section">
        <label class="section-label">
          {{ $t('WHATSAPP_CALLS.TRANSFER_NOTE') }}
          <span class="optional">{{ $t('WHATSAPP_CALLS.OPTIONAL') }}</span>
        </label>

        <textarea
          v-model="transferNote"
          :placeholder="$t('WHATSAPP_CALLS.TRANSFER_NOTE_PLACEHOLDER')"
          class="note-textarea"
          rows="3"
        />
      </div>
    </div>

    <div class="modal-footer">
      <woot-button variant="clear" @click="$emit('close')">
        {{ $t('WHATSAPP_CALLS.CANCEL') }}
      </woot-button>

      <woot-button
        color-scheme="primary"
        :disabled="!canTransfer"
        @click="handleTransfer"
      >
        {{ $t('WHATSAPP_CALLS.TRANSFER') }}
      </woot-button>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.transfer-call-modal {
  .modal-content {
    padding: var(--space-normal);
    max-height: 60vh;
    overflow-y: auto;
  }

  .section-label {
    display: block;
    margin-bottom: var(--space-small);
    font-size: var(--font-size-small);
    font-weight: var(--font-weight-medium);
    color: var(--s-900);

    .optional {
      margin-left: var(--space-micro);
      font-weight: var(--font-weight-normal);
      color: var(--s-600);
      font-size: var(--font-size-mini);
    }
  }

  .transfer-type-section {
    margin-bottom: var(--space-large);

    .transfer-type-options {
      display: flex;
      gap: var(--space-small);
    }
  }

  .selection-section {
    margin-bottom: var(--space-large);
  }

  .agent-search {
    margin-bottom: var(--space-normal);

    .search-input {
      width: 100%;
      padding: var(--space-small);
      border: 1px solid var(--s-200);
      border-radius: var(--border-radius-normal);
      font-size: var(--font-size-small);

      &:focus {
        outline: none;
        border-color: var(--w-500);
      }
    }
  }

  .agent-list {
    max-height: 300px;
    overflow-y: auto;
    border: 1px solid var(--s-200);
    border-radius: var(--border-radius-normal);
  }

  .agent-item {
    display: flex;
    align-items: center;
    gap: var(--space-small);
    padding: var(--space-small);
    cursor: pointer;
    transition: background 0.2s ease;

    &:not(:last-child) {
      border-bottom: 1px solid var(--s-100);
    }

    &:hover {
      background: var(--s-25);
    }

    &.selected {
      background: var(--w-50);
      border-color: var(--w-200);
    }

    .agent-info {
      flex: 1;
      display: flex;
      flex-direction: column;
      gap: var(--space-micro);

      .agent-name {
        font-size: var(--font-size-small);
        font-weight: var(--font-weight-medium);
        color: var(--s-900);
      }

      .agent-status {
        font-size: var(--font-size-mini);
        color: var(--s-600);

        &.status-online {
          color: var(--g-600);
        }

        &.status-busy {
          color: var(--y-600);
        }

        &.status-offline {
          color: var(--s-500);
        }
      }
    }

    .selected-icon {
      color: var(--w-600);
    }
  }

  .empty-state {
    padding: var(--space-large);
    text-align: center;
    color: var(--s-600);

    p {
      margin: 0;
      font-size: var(--font-size-small);
    }
  }

  .note-section {
    .note-textarea {
      width: 100%;
      padding: var(--space-small);
      border: 1px solid var(--s-200);
      border-radius: var(--border-radius-normal);
      font-size: var(--font-size-small);
      font-family: inherit;
      resize: vertical;

      &:focus {
        outline: none;
        border-color: var(--w-500);
      }
    }
  }

  .modal-footer {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-small);
    padding: var(--space-normal);
    border-top: 1px solid var(--s-100);
  }
}
</style>
