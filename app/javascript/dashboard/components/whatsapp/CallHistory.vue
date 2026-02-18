<script>
import { mapGetters } from 'vuex';
import Spinner from 'shared/components/Spinner.vue';
import Multiselect from 'vue-multiselect';
import timeMixin from 'dashboard/mixins/time';
import CallDetailsModal from './CallDetailsModal.vue';

export default {
  name: 'CallHistory',
  components: {
    Spinner,
    Multiselect,
    CallDetailsModal,
  },
  mixins: [timeMixin],
  props: {
    conversationId: {
      type: Number,
      default: null,
    },
  },
  data() {
    return {
      isLoading: false,
      isLoadingMore: false,
      calls: [],
      selectedDirection: null,
      selectedStatus: null,
      currentPage: 1,
      hasMoreCalls: false,
      showDetailsModal: false,
      selectedCall: null,
    };
  },
  computed: {
    ...mapGetters({
      currentUser: 'getCurrentUser',
    }),
    directionOptions() {
      return [
        { label: this.$t('WHATSAPP_CALLS.ALL_DIRECTIONS'), value: null },
        { label: this.$t('WHATSAPP_CALLS.INBOUND'), value: 'inbound' },
        { label: this.$t('WHATSAPP_CALLS.OUTBOUND'), value: 'outbound' },
      ];
    },
    statusOptions() {
      return [
        { label: this.$t('WHATSAPP_CALLS.ALL_STATUSES'), value: null },
        { label: this.$t('WHATSAPP_CALLS.STATUS.COMPLETED'), value: 'ended' },
        { label: this.$t('WHATSAPP_CALLS.STATUS.REJECTED'), value: 'rejected' },
        { label: this.$t('WHATSAPP_CALLS.STATUS.FAILED'), value: 'failed' },
      ];
    },
    filteredCalls() {
      let filtered = [...this.calls];

      if (this.selectedDirection?.value) {
        filtered = filtered.filter(
          call => call.direction === this.selectedDirection.value
        );
      }

      if (this.selectedStatus?.value) {
        filtered = filtered.filter(
          call => call.status === this.selectedStatus.value
        );
      }

      return filtered;
    },
    hasCallHistory() {
      return this.calls.length > 0;
    },
  },
  mounted() {
    this.fetchCallHistory();
  },
  methods: {
    showAlert(message) {
      window.bus.$emit('newToastMessage', { message });
    },
    async fetchCallHistory() {
      this.isLoading = true;

      try {
        // Fetch call history from API
        const response = await this.$store.dispatch(
          'whatsappCalls/fetchHistory',
          {
            conversationId: this.conversationId,
            page: 1,
          }
        );

        this.calls = response.data.calls;
        this.hasMoreCalls = response.data.has_more;
        this.currentPage = 1;
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.FETCH_HISTORY_FAILED'));
        console.error('Failed to fetch call history:', error);
      } finally {
        this.isLoading = false;
      }
    },
    async loadMoreCalls() {
      this.isLoadingMore = true;

      try {
        const response = await this.$store.dispatch(
          'whatsappCalls/fetchHistory',
          {
            conversationId: this.conversationId,
            page: this.currentPage + 1,
          }
        );

        this.calls = [...this.calls, ...response.data.calls];
        this.hasMoreCalls = response.data.has_more;
        this.currentPage += 1;
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.LOAD_MORE_FAILED'));
        console.error('Failed to load more calls:', error);
      } finally {
        this.isLoadingMore = false;
      }
    },
    refreshCallHistory() {
      this.fetchCallHistory();
    },
    applyFilters() {
      // Filters are computed, no action needed
    },
    getCallIcon(call) {
      if (call.direction === 'inbound') {
        return call.status === 'ended' ? 'call-inbound' : 'call-missed';
      }
      return call.status === 'ended' ? 'call-outbound' : 'call-end';
    },
    getDirectionText(direction) {
      return direction === 'inbound'
        ? this.$t('WHATSAPP_CALLS.INBOUND_CALL')
        : this.$t('WHATSAPP_CALLS.OUTBOUND_CALL');
    },
    getStatusText(status) {
      const statusMap = {
        ended: this.$t('WHATSAPP_CALLS.STATUS.COMPLETED'),
        rejected: this.$t('WHATSAPP_CALLS.STATUS.REJECTED'),
        failed: this.$t('WHATSAPP_CALLS.STATUS.FAILED'),
      };
      return statusMap[status] || status;
    },
    formatDateTime(timestamp) {
      return this.dynamicTime(timestamp);
    },
    openCallDetails(call) {
      this.selectedCall = call;
      this.showDetailsModal = true;
    },
    closeDetailsModal() {
      this.showDetailsModal = false;
      this.selectedCall = null;
    },
    playRecording(call) {
      this.$emit('play-recording', call);
    },
    async exportCallHistory() {
      try {
        // Export call history as CSV
        const csv = this.generateCSV();
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `call-history-${Date.now()}.csv`;
        link.click();
        window.URL.revokeObjectURL(url);

        this.showAlert(this.$t('WHATSAPP_CALLS.EXPORT_SUCCESS'));
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.EXPORT_FAILED'));
        console.error('Failed to export call history:', error);
      }
    },
    generateCSV() {
      const headers = [
        'Date',
        'Direction',
        'Status',
        'Duration',
        'Contact',
        'Phone Number',
      ];

      const rows = this.calls.map(call => [
        new Date(call.initiated_at).toISOString(),
        call.direction,
        call.status,
        call.duration || '0s',
        call.contact_name || '',
        call.contact_number || '',
      ]);

      const csvContent = [
        headers.join(','),
        ...rows.map(row => row.join(',')),
      ].join('\n');

      return csvContent;
    },
  },
};
</script>

<template>
  <div class="call-history-container">
    <div class="call-history-header">
      <h3 class="title">
        {{ $t('WHATSAPP_CALLS.CALL_HISTORY') }}
      </h3>
      <div class="header-actions">
        <woot-button
          icon="arrow-download"
          size="small"
          variant="clear"
          :disabled="!hasCallHistory"
          @click="exportCallHistory"
        >
          {{ $t('WHATSAPP_CALLS.EXPORT') }}
        </woot-button>
        <woot-button
          icon="arrow-sync"
          size="small"
          variant="clear"
          :is-loading="isLoading"
          @click="refreshCallHistory"
        >
          {{ $t('WHATSAPP_CALLS.REFRESH') }}
        </woot-button>
      </div>
    </div>

    <!-- Filters -->
    <div class="call-filters">
      <Multiselect
        v-model="selectedDirection"
        :options="directionOptions"
        :placeholder="$t('WHATSAPP_CALLS.FILTER_BY_DIRECTION')"
        label="label"
        track-by="value"
        @select="applyFilters"
      />
      <Multiselect
        v-model="selectedStatus"
        :options="statusOptions"
        :placeholder="$t('WHATSAPP_CALLS.FILTER_BY_STATUS')"
        label="label"
        track-by="value"
        @select="applyFilters"
      />
    </div>

    <!-- Call List -->
    <div v-if="isLoading" class="loading-state">
      <Spinner size="small" />
      <p>{{ $t('WHATSAPP_CALLS.LOADING_HISTORY') }}</p>
    </div>

    <div v-else-if="filteredCalls.length === 0" class="empty-state">
      <fluent-icon icon="call" size="48" />
      <p>{{ $t('WHATSAPP_CALLS.NO_CALL_HISTORY') }}</p>
    </div>

    <div v-else class="call-list">
      <div
        v-for="call in filteredCalls"
        :key="call.id"
        class="call-item"
        :class="`call-${call.direction}`"
        @click="openCallDetails(call)"
      >
        <div class="call-icon">
          <fluent-icon
            :icon="getCallIcon(call)"
            size="24"
            :class="`status-${call.status}`"
          />
        </div>

        <div class="call-info">
          <div class="call-primary-info">
            <span class="call-direction">
              {{ getDirectionText(call.direction) }}
            </span>
            <span class="call-status" :class="`status-${call.status}`">
              {{ getStatusText(call.status) }}
            </span>
          </div>

          <div class="call-meta">
            <span class="call-date">
              {{ formatDateTime(call.initiated_at) }}
            </span>
            <span v-if="call.duration" class="call-duration">
              {{ call.duration }}
            </span>
          </div>
        </div>

        <div v-if="call.status === 'ended'" class="call-actions">
          <woot-button
            v-if="call.recording_url"
            icon="play"
            size="tiny"
            variant="clear"
            @click.stop="playRecording(call)"
          />
          <woot-button icon="chevron-right" size="tiny" variant="clear" />
        </div>
      </div>
    </div>

    <!-- Pagination -->
    <div v-if="hasMoreCalls" class="pagination">
      <woot-button
        variant="clear"
        :is-loading="isLoadingMore"
        @click="loadMoreCalls"
      >
        {{ $t('WHATSAPP_CALLS.LOAD_MORE') }}
      </woot-button>
    </div>

    <!-- Call Details Modal -->
    <woot-modal v-model:show="showDetailsModal" :on-close="closeDetailsModal">
      <CallDetailsModal
        v-if="selectedCall"
        :call="selectedCall"
        @close="closeDetailsModal"
      />
    </woot-modal>
  </div>
</template>

<style lang="scss" scoped>
.call-history-container {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.call-history-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-normal);
  border-bottom: 1px solid var(--s-100);

  .title {
    margin: 0;
    font-size: var(--font-size-medium);
    font-weight: var(--font-weight-bold);
    color: var(--s-900);
  }

  .header-actions {
    display: flex;
    gap: var(--space-small);
  }
}

.call-filters {
  display: flex;
  gap: var(--space-small);
  padding: var(--space-normal);
  border-bottom: 1px solid var(--s-100);
}

.loading-state,
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: var(--space-larger);
  color: var(--s-600);
  text-align: center;
  flex: 1;

  p {
    margin-top: var(--space-small);
    font-size: var(--font-size-small);
  }
}

.call-list {
  flex: 1;
  overflow-y: auto;
}

.call-item {
  display: flex;
  align-items: center;
  gap: var(--space-small);
  padding: var(--space-normal);
  border-bottom: 1px solid var(--s-75);
  cursor: pointer;
  transition: background 0.2s ease;

  &:hover {
    background: var(--s-25);
  }

  &.call-inbound {
    border-left: 3px solid var(--b-500);
  }

  &.call-outbound {
    border-left: 3px solid var(--g-500);
  }

  .call-icon {
    flex-shrink: 0;

    .status-ended {
      color: var(--g-600);
    }

    .status-rejected,
    .status-failed {
      color: var(--r-500);
    }
  }

  .call-info {
    flex: 1;
    min-width: 0;

    .call-primary-info {
      display: flex;
      align-items: center;
      gap: var(--space-small);
      margin-bottom: var(--space-micro);

      .call-direction {
        font-size: var(--font-size-small);
        font-weight: var(--font-weight-medium);
        color: var(--s-900);
      }

      .call-status {
        font-size: var(--font-size-mini);
        padding: 2px 8px;
        border-radius: var(--border-radius-small);

        &.status-ended {
          background: var(--g-50);
          color: var(--g-700);
        }

        &.status-rejected,
        &.status-failed {
          background: var(--r-50);
          color: var(--r-700);
        }
      }
    }

    .call-meta {
      display: flex;
      align-items: center;
      gap: var(--space-small);
      font-size: var(--font-size-mini);
      color: var(--s-600);

      .call-duration {
        &::before {
          content: '•';
          margin-right: var(--space-small);
        }
      }
    }
  }

  .call-actions {
    display: flex;
    gap: var(--space-micro);
    flex-shrink: 0;
  }
}

.pagination {
  display: flex;
  justify-content: center;
  padding: var(--space-normal);
  border-top: 1px solid var(--s-100);
}
</style>
