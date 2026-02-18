<script>
import { mapGetters } from 'vuex';
import Spinner from 'shared/components/Spinner.vue';
import Multiselect from 'vue-multiselect';
import WhatsappCallsAPI from '../../api/whatsapp/calls';

export default {
  name: 'WhatsAppCallsAnalytics',
  components: {
    Spinner,
    Multiselect,
  },
  data() {
    return {
      isLoading: false,
      isExporting: false,
      analyticsData: null,
      dateRange: {
        start: this.getDefaultStartDate(),
        end: new Date(),
      },
      selectedInbox: null,
    };
  },
  computed: {
    ...mapGetters({
      currentAccountId: 'getCurrentAccountId',
      inboxes: 'inboxes/getInboxes',
    }),
    inboxOptions() {
      return this.inboxes.filter(
        inbox =>
          inbox.channel_type === 'Channel::Whatsapp' && inbox.calling_enabled
      );
    },
    inboundPercentage() {
      if (!this.analyticsData || this.analyticsData.total_calls === 0) return 0;
      return (
        (this.analyticsData.inbound_calls / this.analyticsData.total_calls) *
        100
      );
    },
    outboundPercentage() {
      if (!this.analyticsData || this.analyticsData.total_calls === 0) return 0;
      return (
        (this.analyticsData.outbound_calls / this.analyticsData.total_calls) *
        100
      );
    },
  },
  mounted() {
    this.fetchAnalytics();
  },
  methods: {
    async fetchAnalytics() {
      this.isLoading = true;

      try {
        const params = {
          accountId: this.currentAccountId,
          startDate: this.dateRange.start.toISOString(),
          endDate: this.dateRange.end.toISOString(),
        };

        if (this.selectedInbox) {
          params.inboxId = this.selectedInbox.id;
        }

        const response = await WhatsappCallsAPI.getAnalytics(params);
        this.analyticsData = response.data.analytics;
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.ANALYTICS.FETCH_ERROR'));
        console.error('Failed to fetch analytics:', error);
      } finally {
        this.isLoading = false;
      }
    },

    async exportAnalytics() {
      this.isExporting = true;

      try {
        const csvContent = this.generateCSV();
        const blob = new Blob([csvContent], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `whatsapp-calls-analytics-${Date.now()}.csv`;
        link.click();
        window.URL.revokeObjectURL(url);

        this.showAlert(this.$t('WHATSAPP_CALLS.ANALYTICS.EXPORT_SUCCESS'));
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.ANALYTICS.EXPORT_ERROR'));
        console.error('Failed to export analytics:', error);
      } finally {
        this.isExporting = false;
      }
    },

    generateCSV() {
      const headers = ['Metric', 'Value'];

      const rows = [
        ['Total Calls', this.analyticsData.total_calls],
        ['Inbound Calls', this.analyticsData.inbound_calls],
        ['Outbound Calls', this.analyticsData.outbound_calls],
        ['Completed Calls', this.analyticsData.completed_calls],
        ['Failed Calls', this.analyticsData.failed_calls],
        ['Success Rate (%)', this.analyticsData.success_rate],
        ['Average Duration (seconds)', this.analyticsData.average_duration],
        ['Total Duration (seconds)', this.analyticsData.total_duration],
        ['Date Range Start', this.dateRange.start.toISOString()],
        ['Date Range End', this.dateRange.end.toISOString()],
      ];

      const csvContent = [
        headers.join(','),
        ...rows.map(row => row.join(',')),
      ].join('\n');

      return csvContent;
    },

    formatDuration(seconds) {
      if (!seconds) return '0:00';

      const minutes = Math.floor(seconds / 60);
      const secs = Math.floor(seconds % 60);
      return `${minutes}:${secs.toString().padStart(2, '0')}`;
    },

    calculateFailureRate() {
      if (!this.analyticsData || this.analyticsData.total_calls === 0) return 0;
      return (
        (this.analyticsData.failed_calls / this.analyticsData.total_calls) *
        100
      ).toFixed(1);
    },

    getDefaultStartDate() {
      const date = new Date();
      date.setDate(date.getDate() - 30); // Last 30 days
      return date;
    },
  },
};
</script>

<template>
  <div class="whatsapp-calls-analytics">
    <!-- Header with Date Range Selector -->
    <div class="analytics-header">
      <h2 class="page-title">
        {{ $t('WHATSAPP_CALLS.ANALYTICS.TITLE') }}
      </h2>

      <div class="date-range-selector">
        <woot-date-range-picker
          v-model="dateRange"
          :placeholder="$t('WHATSAPP_CALLS.ANALYTICS.SELECT_DATE_RANGE')"
          @change="fetchAnalytics"
        />

        <Multiselect
          v-model="selectedInbox"
          :options="inboxOptions"
          :placeholder="$t('WHATSAPP_CALLS.ANALYTICS.ALL_INBOXES')"
          label="name"
          track-by="id"
          :show-labels="false"
          @select="fetchAnalytics"
        />
      </div>
    </div>

    <!-- Loading State -->
    <div v-if="isLoading" class="loading-container">
      <Spinner size="large" />
      <p>{{ $t('WHATSAPP_CALLS.ANALYTICS.LOADING') }}</p>
    </div>

    <!-- Analytics Content -->
    <div v-else-if="analyticsData" class="analytics-content">
      <!-- Summary Cards -->
      <div class="summary-cards">
        <div class="card card-total">
          <div class="card-icon">
            <fluent-icon icon="call" size="32" />
          </div>
          <div class="card-content">
            <h3 class="card-value">{{ analyticsData.total_calls }}</h3>
            <p class="card-label">
              {{ $t('WHATSAPP_CALLS.ANALYTICS.TOTAL_CALLS') }}
            </p>
          </div>
        </div>

        <div class="card card-success">
          <div class="card-icon">
            <fluent-icon icon="checkmark-circle" size="32" />
          </div>
          <div class="card-content">
            <h3 class="card-value">{{ analyticsData.completed_calls }}</h3>
            <p class="card-label">
              {{ $t('WHATSAPP_CALLS.ANALYTICS.COMPLETED_CALLS') }}
            </p>
            <span class="card-subtitle">
              {{ analyticsData.success_rate }}%
              {{ $t('WHATSAPP_CALLS.ANALYTICS.SUCCESS_RATE') }}
            </span>
          </div>
        </div>

        <div class="card card-duration">
          <div class="card-icon">
            <fluent-icon icon="timer" size="32" />
          </div>
          <div class="card-content">
            <h3 class="card-value">
              {{ formatDuration(analyticsData.average_duration) }}
            </h3>
            <p class="card-label">
              {{ $t('WHATSAPP_CALLS.ANALYTICS.AVG_DURATION') }}
            </p>
            <span class="card-subtitle">
              {{ formatDuration(analyticsData.total_duration) }}
              {{ $t('WHATSAPP_CALLS.ANALYTICS.TOTAL') }}
            </span>
          </div>
        </div>

        <div class="card card-failed">
          <div class="card-icon">
            <fluent-icon icon="dismiss-circle" size="32" />
          </div>
          <div class="card-content">
            <h3 class="card-value">{{ analyticsData.failed_calls }}</h3>
            <p class="card-label">
              {{ $t('WHATSAPP_CALLS.ANALYTICS.FAILED_CALLS') }}
            </p>
            <span class="card-subtitle">
              {{ calculateFailureRate() }}%
              {{ $t('WHATSAPP_CALLS.ANALYTICS.FAILURE_RATE') }}
            </span>
          </div>
        </div>
      </div>

      <!-- Call Direction Breakdown -->
      <div class="chart-section">
        <div class="chart-card">
          <h3 class="chart-title">
            {{ $t('WHATSAPP_CALLS.ANALYTICS.CALL_DIRECTION') }}
          </h3>
          <div class="direction-stats">
            <div class="stat-item inbound">
              <div class="stat-icon">
                <fluent-icon icon="call-inbound" size="24" />
              </div>
              <div class="stat-content">
                <span class="stat-value">{{
                  analyticsData.inbound_calls
                }}</span>
                <span class="stat-label">{{
                  $t('WHATSAPP_CALLS.INBOUND_CALL')
                }}</span>
                <div class="stat-bar">
                  <div
                    class="stat-fill inbound-fill"
                    :style="{ width: `${inboundPercentage}%` }"
                  />
                </div>
              </div>
            </div>

            <div class="stat-item outbound">
              <div class="stat-icon">
                <fluent-icon icon="call-outbound" size="24" />
              </div>
              <div class="stat-content">
                <span class="stat-value">{{
                  analyticsData.outbound_calls
                }}</span>
                <span class="stat-label">{{
                  $t('WHATSAPP_CALLS.OUTBOUND_CALL')
                }}</span>
                <div class="stat-bar">
                  <div
                    class="stat-fill outbound-fill"
                    :style="{ width: `${outboundPercentage}%` }"
                  />
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Call Status Breakdown -->
        <div class="chart-card">
          <h3 class="chart-title">
            {{ $t('WHATSAPP_CALLS.ANALYTICS.CALL_STATUS') }}
          </h3>
          <div class="status-list">
            <div class="status-item completed">
              <span class="status-label">{{
                $t('WHATSAPP_CALLS.STATUS.COMPLETED')
              }}</span>
              <span class="status-value">{{
                analyticsData.completed_calls
              }}</span>
            </div>
            <div class="status-item failed">
              <span class="status-label">{{
                $t('WHATSAPP_CALLS.STATUS.FAILED')
              }}</span>
              <span class="status-value">{{ analyticsData.failed_calls }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Additional Metrics -->
      <div class="metrics-section">
        <div class="metric-card">
          <h4 class="metric-title">
            {{ $t('WHATSAPP_CALLS.ANALYTICS.PEAK_HOURS') }}
          </h4>
          <div class="metric-content">
            <p class="metric-description">
              {{ $t('WHATSAPP_CALLS.ANALYTICS.PEAK_HOURS_DESC') }}
            </p>
            <!-- TODO: Add peak hours chart -->
            <div class="coming-soon">
              {{ $t('WHATSAPP_CALLS.ANALYTICS.COMING_SOON') }}
            </div>
          </div>
        </div>

        <div class="metric-card">
          <h4 class="metric-title">
            {{ $t('WHATSAPP_CALLS.ANALYTICS.AGENT_PERFORMANCE') }}
          </h4>
          <div class="metric-content">
            <p class="metric-description">
              {{ $t('WHATSAPP_CALLS.ANALYTICS.AGENT_PERFORMANCE_DESC') }}
            </p>
            <!-- TODO: Add agent performance table -->
            <div class="coming-soon">
              {{ $t('WHATSAPP_CALLS.ANALYTICS.COMING_SOON') }}
            </div>
          </div>
        </div>
      </div>

      <!-- Export Button -->
      <div class="analytics-footer">
        <woot-button
          icon="arrow-download"
          :is-loading="isExporting"
          @click="exportAnalytics"
        >
          {{ $t('WHATSAPP_CALLS.ANALYTICS.EXPORT_REPORT') }}
        </woot-button>
      </div>
    </div>

    <!-- Empty State -->
    <div v-else class="empty-state">
      <fluent-icon icon="chart-multiple" size="48" />
      <h3>{{ $t('WHATSAPP_CALLS.ANALYTICS.NO_DATA') }}</h3>
      <p>{{ $t('WHATSAPP_CALLS.ANALYTICS.NO_DATA_DESC') }}</p>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.whatsapp-calls-analytics {
  padding: var(--space-normal);
}

.analytics-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--space-large);
  flex-wrap: wrap;
  gap: var(--space-normal);

  .page-title {
    margin: 0;
    font-size: var(--font-size-large);
    font-weight: var(--font-weight-bold);
    color: var(--s-900);
  }

  .date-range-selector {
    display: flex;
    gap: var(--space-small);
  }
}

.loading-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: var(--space-larger);

  p {
    margin-top: var(--space-small);
    color: var(--s-600);
  }
}

.summary-cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: var(--space-normal);
  margin-bottom: var(--space-large);

  .card {
    display: flex;
    gap: var(--space-normal);
    padding: var(--space-large);
    background: var(--white);
    border-radius: var(--border-radius-large);
    border: 1px solid var(--s-100);
    transition: transform 0.2s ease, box-shadow 0.2s ease;

    &:hover {
      transform: translateY(-2px);
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
    }

    .card-icon {
      flex-shrink: 0;
      display: flex;
      align-items: center;
      justify-content: center;
      width: 60px;
      height: 60px;
      border-radius: var(--border-radius-normal);
    }

    .card-content {
      flex: 1;

      .card-value {
        margin: 0 0 var(--space-micro);
        font-size: 32px;
        font-weight: var(--font-weight-bold);
        color: var(--s-900);
        line-height: 1;
      }

      .card-label {
        margin: 0 0 var(--space-micro);
        font-size: var(--font-size-small);
        color: var(--s-600);
        text-transform: uppercase;
        letter-spacing: 0.5px;
        font-weight: var(--font-weight-medium);
      }

      .card-subtitle {
        font-size: var(--font-size-mini);
        color: var(--s-500);
      }
    }

    &.card-total .card-icon {
      background: var(--b-50);
      color: var(--b-600);
    }

    &.card-success .card-icon {
      background: var(--g-50);
      color: var(--g-600);
    }

    &.card-duration .card-icon {
      background: var(--y-50);
      color: var(--y-600);
    }

    &.card-failed .card-icon {
      background: var(--r-50);
      color: var(--r-600);
    }
  }
}

.chart-section {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
  gap: var(--space-normal);
  margin-bottom: var(--space-large);
}

.chart-card {
  padding: var(--space-large);
  background: var(--white);
  border-radius: var(--border-radius-large);
  border: 1px solid var(--s-100);

  .chart-title {
    margin: 0 0 var(--space-normal);
    font-size: var(--font-size-medium);
    font-weight: var(--font-weight-medium);
    color: var(--s-900);
  }
}

.direction-stats {
  display: flex;
  flex-direction: column;
  gap: var(--space-large);

  .stat-item {
    display: flex;
    gap: var(--space-normal);

    .stat-icon {
      flex-shrink: 0;
      display: flex;
      align-items: center;
      justify-center;
      width: 48px;
      height: 48px;
      border-radius: var(--border-radius-normal);
    }

    &.inbound .stat-icon {
      background: var(--b-50);
      color: var(--b-600);
    }

    &.outbound .stat-icon {
      background: var(--g-50);
      color: var(--g-600);
    }

    .stat-content {
      flex: 1;

      .stat-value {
        display: block;
        font-size: var(--font-size-large);
        font-weight: var(--font-weight-bold);
        color: var(--s-900);
        margin-bottom: var(--space-micro);
      }

      .stat-label {
        display: block;
        font-size: var(--font-size-small);
        color: var(--s-600);
        margin-bottom: var(--space-small);
      }

      .stat-bar {
        height: 8px;
        background: var(--s-100);
        border-radius: 4px;
        overflow: hidden;

        .stat-fill {
          height: 100%;
          transition: width 0.3s ease;

          &.inbound-fill {
            background: var(--b-500);
          }

          &.outbound-fill {
            background: var(--g-500);
          }
        }
      }
    }
  }
}

.status-list {
  .status-item {
    display: flex;
    justify-content: space-between;
    padding: var(--space-normal);
    border-bottom: 1px solid var(--s-100);

    &:last-child {
      border-bottom: none;
    }

    .status-label {
      font-size: var(--font-size-small);
      color: var(--s-700);
    }

    .status-value {
      font-size: var(--font-size-small);
      font-weight: var(--font-weight-bold);
      color: var(--s-900);
    }
  }
}

.metrics-section {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
  gap: var(--space-normal);
  margin-bottom: var(--space-large);
}

.metric-card {
  padding: var(--space-large);
  background: var(--white);
  border-radius: var(--border-radius-large);
  border: 1px solid var(--s-100);

  .metric-title {
    margin: 0 0 var(--space-normal);
    font-size: var(--font-size-medium);
    font-weight: var(--font-weight-medium);
    color: var(--s-900);
  }

  .metric-description {
    margin: 0 0 var(--space-normal);
    font-size: var(--font-size-small);
    color: var(--s-600);
  }

  .coming-soon {
    padding: var(--space-large);
    text-align: center;
    color: var(--s-500);
    font-style: italic;
    background: var(--s-25);
    border-radius: var(--border-radius-normal);
  }
}

.analytics-footer {
  display: flex;
  justify-content: flex-end;
  padding-top: var(--space-normal);
  border-top: 1px solid var(--s-100);
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: var(--space-larger);
  text-align: center;

  h3 {
    margin: var(--space-normal) 0 var(--space-small);
    color: var(--s-900);
  }

  p {
    margin: 0;
    color: var(--s-600);
  }
}
</style>
