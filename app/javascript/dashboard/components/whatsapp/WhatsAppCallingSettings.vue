<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import SettingsSection from 'dashboard/components/SettingsSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import countries from 'shared/constants/countries.js';
import InboxesAPI from '../../api/inboxes';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();

const DAYS = [
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY',
];

const DAY_LABEL_KEYS = {
  MONDAY: 'DAY_MONDAY',
  TUESDAY: 'DAY_TUESDAY',
  WEDNESDAY: 'DAY_WEDNESDAY',
  THURSDAY: 'DAY_THURSDAY',
  FRIDAY: 'DAY_FRIDAY',
  SATURDAY: 'DAY_SATURDAY',
  SUNDAY: 'DAY_SUNDAY',
};

const CHECKBOX_CLASSES =
  'w-4 h-4 text-woot-600 bg-slate-100 border-slate-300 rounded focus:ring-woot-500 dark:focus:ring-woot-600 dark:ring-offset-slate-800 focus:ring-2 dark:bg-slate-700 dark:border-slate-600';

const INPUT_CLASSES =
  'w-full px-3 py-2 text-sm border border-n-weak rounded-md bg-n-solid-1 text-n-slate-12 focus:ring-2 focus:ring-woot-500 focus:border-transparent';

const TIME_INPUT_CLASSES =
  'text-sm border border-n-weak rounded-md px-2 py-1.5 bg-n-solid-1 text-n-slate-12 focus:ring-2 focus:ring-woot-500 focus:border-transparent';

const isSaving = ref(false);

const visibilityOptions = computed(() => [
  { value: 'DEFAULT', label: t('WHATSAPP_CALLS.SETTINGS.CALL_ICON_DEFAULT') },
  { value: 'DISABLE_ALL', label: t('WHATSAPP_CALLS.SETTINGS.CALL_ICON_HIDDEN') },
]);

const selectedCountries = computed({
  get: () =>
    form.call_icons_countries
      ? form.call_icons_countries
          .split(',')
          .map(c => c.trim().toUpperCase())
          .filter(Boolean)
          .map(code => countries.find(c => c.id === code))
          .filter(Boolean)
      : [],
  set: vals => {
    form.call_icons_countries = vals.map(c => c.id).join(', ');
  },
});

const selectedVisibility = computed({
  get: () =>
    visibilityOptions.value.find(o => o.value === form.call_icon_visibility) ??
    visibilityOptions.value[0],
  set: val => {
    form.call_icon_visibility = val?.value ?? 'DEFAULT';
  },
});

function defaultSchedule() {
  return DAYS.map(day => ({
    day,
    enabled: !['SATURDAY', 'SUNDAY'].includes(day),
    open_time: '09:00',
    close_time: '17:00',
  }));
}

const form = reactive({
  calling_enabled: false,
  calling_expiry_date: '',
  recording_enabled: false,
  call_icon_visibility: 'DEFAULT',
  callback_permission_status: 'ENABLED',
  call_icons_countries: '',
  call_hours_enabled: false,
  call_hours_timezone: 'UTC',
  call_hours_schedule: defaultSchedule(),
  call_hours_holidays: [],
});

function loadSettings() {
  const config = props.inbox.calling_config || {};
  form.calling_enabled = props.inbox.calling_enabled || false;
  form.calling_expiry_date = config.calling_expiry_date || '';
  form.recording_enabled = config.recording_enabled || false;
  form.call_icon_visibility =
    config.call_icon_visibility === 'HIDDEN'
      ? 'DISABLE_ALL'
      : config.call_icon_visibility || 'DEFAULT';
  form.callback_permission_status =
    config.callback_permission_status || 'ENABLED';
  form.call_icons_countries = (config.call_icons_countries || []).join(', ');
  form.call_hours_enabled = config.call_hours_enabled || false;
  form.call_hours_timezone = config.call_hours_timezone || 'UTC';
  form.call_hours_schedule = config.call_hours_schedule?.length
    ? DAYS.map(day => {
        const existing = config.call_hours_schedule.find(s => s.day === day);
        return existing
          ? { ...existing }
          : { day, enabled: false, open_time: '09:00', close_time: '17:00' };
      })
    : defaultSchedule();
  form.call_hours_holidays = config.call_hours_holidays
    ? config.call_hours_holidays.map(h => ({ ...h }))
    : [];
}

function parseMetaTime(str) {
  if (!str) return '09:00';
  const s = String(str).padStart(4, '0');
  return `${s.slice(0, 2)}:${s.slice(2)}`;
}

function applyMetaSettings(calling) {
  if (calling.status !== undefined) {
    form.calling_enabled = calling.status === 'ENABLED';
  }
  if (calling.call_icon_visibility) {
    form.call_icon_visibility = calling.call_icon_visibility;
  }
  if (calling.callback_permission_status) {
    form.callback_permission_status = calling.callback_permission_status;
  }
  if (calling.call_icons?.restrict_to_user_countries?.length) {
    form.call_icons_countries =
      calling.call_icons.restrict_to_user_countries.join(', ');
  }
  if (calling.call_hours) {
    const ch = calling.call_hours;
    form.call_hours_enabled = ch.status === 'ENABLED';
    if (ch.timezone_id) form.call_hours_timezone = ch.timezone_id;
    if (ch.weekly_operating_hours?.length) {
      form.call_hours_schedule = DAYS.map(day => {
        const entry = ch.weekly_operating_hours.find(
          h => h.day_of_week === day
        );
        return {
          day,
          enabled: !!entry,
          open_time: entry ? parseMetaTime(entry.open_time) : '09:00',
          close_time: entry ? parseMetaTime(entry.close_time) : '17:00',
        };
      });
    }
    if (ch.holiday_schedule?.length) {
      form.call_hours_holidays = ch.holiday_schedule.map(h => ({
        date: h.date,
        start_time: parseMetaTime(h.start_time),
        end_time: parseMetaTime(h.end_time),
      }));
    }
  }
}

function addHoliday() {
  form.call_hours_holidays.push({
    date: '',
    start_time: '00:00',
    end_time: '23:59',
  });
}

function removeHoliday(index) {
  form.call_hours_holidays.splice(index, 1);
}

async function saveSettings() {
  isSaving.value = true;
  try {
    await InboxesAPI.updateChannel(props.inbox.id, {
      channel: {
        calling_enabled: form.calling_enabled,
        calling_config: {
          calling_expiry_date: form.calling_expiry_date || null,
          recording_enabled: form.recording_enabled,
          call_icon_visibility: form.call_icon_visibility,
          callback_permission_status: form.callback_permission_status,
          call_icons_countries: form.call_icons_countries
            ? form.call_icons_countries
                .split(',')
                .map(c => c.trim().toUpperCase())
                .filter(Boolean)
            : [],
          call_hours_enabled: form.call_hours_enabled,
          call_hours_timezone: form.call_hours_timezone,
          call_hours_schedule: form.call_hours_schedule,
          call_hours_holidays: form.call_hours_holidays,
        },
      },
    });
    useAlert(t('WHATSAPP_CALLS.SETTINGS.SUCCESS'));
    store.dispatch('inboxes/get');
  } catch {
    useAlert(t('WHATSAPP_CALLS.SETTINGS.ERROR_SAVING'));
  } finally {
    isSaving.value = false;
  }
}

async function syncFromMeta() {
  try {
    const { data } = await InboxesAPI.getMetaCallingSettings(props.inbox.id);
    if (!data.meta_error) {
      applyMetaSettings(data.calling || {});
    }
  } catch {
    // silently fall back to locally stored settings
  }
}

async function initSettings() {
  loadSettings();
  await syncFromMeta();
}

watch(() => props.inbox, initSettings);
onMounted(initSettings);
</script>

<template>
  <form @submit.prevent="saveSettings">
    <!-- Section 1: General -->
    <SettingsSection
      :title="$t('WHATSAPP_CALLS.SETTINGS.TITLE')"
      :sub-title="$t('WHATSAPP_CALLS.SETTINGS.DESCRIPTION')"
    >
      <div class="space-y-4 md:max-w-4xl">
        <div class="border-b border-n-weak pb-4">
          <label class="flex items-center gap-3 cursor-pointer">
            <input
              v-model="form.calling_enabled"
              type="checkbox"
              :class="CHECKBOX_CLASSES"
            />
            <div>
              <span class="font-medium text-n-slate-12">
                {{ $t('WHATSAPP_CALLS.SETTINGS.ENABLE_CALLING') }}
              </span>
              <p class="text-xs text-n-slate-11 mt-0.5">
                {{ $t('WHATSAPP_CALLS.SETTINGS.ENABLE_CALLING_HELP') }}
              </p>
            </div>
          </label>
        </div>
        <div v-if="form.calling_enabled" class="pt-1">
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{ $t('WHATSAPP_CALLS.SETTINGS.CALLING_EXPIRY_DATE') }}
          </label>
          <p class="text-xs text-n-slate-11 mb-2">
            {{ $t('WHATSAPP_CALLS.SETTINGS.CALLING_EXPIRY_DATE_HELP') }}
          </p>
          <div class="flex items-center gap-2">
            <input
              v-model="form.calling_expiry_date"
              type="date"
              class="px-3 py-1.5 text-sm rounded-lg border border-n-weak bg-n-surface-1 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
            />
            <button
              v-if="form.calling_expiry_date"
              type="button"
              class="text-xs text-n-slate-11 hover:text-n-ruby-9 transition-colors"
              @click="form.calling_expiry_date = ''"
            >
              {{ $t('WHATSAPP_CALLS.SETTINGS.CALLING_EXPIRY_DATE_CLEAR') }}
            </button>
          </div>
        </div>
        <div v-if="form.calling_enabled" class="flex items-start gap-3 pt-1">
          <div class="flex-1">
            <label class="block text-sm font-medium text-n-slate-12 mb-1">
              {{ $t('WHATSAPP_CALLS.SETTINGS.CALLING_EXPIRY_DATE') }}
            </label>
            <p class="text-xs text-n-slate-11 mb-2">
              {{ $t('WHATSAPP_CALLS.SETTINGS.CALLING_EXPIRY_DATE_HELP') }}
            </p>
            <input
              v-model="form.calling_expiry_date"
              type="date"
              class="px-3 py-1.5 text-sm rounded-lg border border-n-weak bg-n-surface-1 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand w-48"
            />
            <button
              v-if="form.calling_expiry_date"
              type="button"
              class="ml-2 text-xs text-n-slate-11 hover:text-n-ruby-9"
              @click="form.calling_expiry_date = ''"
            >
              {{ $t('WHATSAPP_CALLS.SETTINGS.CALLING_EXPIRY_DATE_CLEAR') }}
            </button>
          </div>
        </div>
      </div>
    </SettingsSection>

    <template v-if="form.calling_enabled">
      <!-- Section 2: Meta settings -->
      <SettingsSection
        :title="$t('WHATSAPP_CALLS.SETTINGS.META_SETTINGS_TITLE')"
        :sub-title="$t('WHATSAPP_CALLS.SETTINGS.META_SETTINGS_DESCRIPTION')"
      >
        <div class="space-y-4 md:max-w-4xl">
          <div>
            <WithLabel
              name="call_icon_visibility"
              :label="$t('WHATSAPP_CALLS.SETTINGS.CALL_ICON_VISIBILITY')"
              :help-message="$t('WHATSAPP_CALLS.SETTINGS.CALL_ICON_VISIBILITY_HELP')"
            >
              <multiselect
                v-model="selectedVisibility"
                :options="visibilityOptions"
                track-by="value"
                label="label"
                :allow-empty="false"
                :show-labels="false"
                :searchable="false"
                :placeholder="$t('WHATSAPP_CALLS.SETTINGS.CALL_ICON_VISIBILITY')"
              />
            </WithLabel>
          </div>

            <WithLabel
              name="call_icons_countries"
              :label="$t('WHATSAPP_CALLS.SETTINGS.CALL_ICONS_COUNTRIES')"
              :help-message="$t('WHATSAPP_CALLS.SETTINGS.CALL_ICONS_COUNTRIES_HELP')"
            >
              <multiselect
                v-model="selectedCountries"
                :options="countries"
                track-by="id"
                label="name"
                :multiple="true"
                :close-on-select="false"
                :show-labels="false"
                :searchable="true"
                :placeholder="$t('WHATSAPP_CALLS.SETTINGS.CALL_ICONS_COUNTRIES')"
              >
                <template #option="{ option }">
                  <span>{{ option.emoji }} {{ option.name }}</span>
                </template>
                <template #tag="{ option, remove }">
                  <span class="multiselect__tag">
                    <span>{{ option.emoji }} {{ option.id }}</span>
                    <i class="multiselect__tag-icon" @click="remove(option)" />
                  </span>
                </template>
              </multiselect>
            </WithLabel>

          <div class="border-t border-n-weak pt-4 space-y-3">
            <div class="border-b border-n-weak pb-3">
              <label class="flex items-center gap-3 cursor-pointer">
                <input
                  v-model="form.callback_permission_status"
                  type="checkbox"
                  true-value="ENABLED"
                  false-value="DISABLED"
                  :class="CHECKBOX_CLASSES"
                />
                <div>
                  <span class="font-medium text-n-slate-12">
                    {{ $t('WHATSAPP_CALLS.SETTINGS.CALLBACK_PERMISSION') }}
                  </span>
                  <p class="text-xs text-n-slate-11 mt-0.5">
                    {{ $t('WHATSAPP_CALLS.SETTINGS.CALLBACK_PERMISSION_HELP') }}
                  </p>
                </div>
              </label>
            </div>
            <label class="flex items-center gap-3 cursor-pointer">
              <input
                v-model="form.recording_enabled"
                type="checkbox"
                :class="CHECKBOX_CLASSES"
              />
              <div>
                <span class="font-medium text-n-slate-12">
                  {{ $t('WHATSAPP_CALLS.SETTINGS.ENABLE_RECORDING') }}
                </span>
                <p class="text-xs text-n-slate-11 mt-0.5">
                  {{ $t('WHATSAPP_CALLS.SETTINGS.ENABLE_RECORDING_HELP') }}
                </p>
              </div>
            </label>
          </div>
        </div>
      </SettingsSection>

      <!-- Section 3: Call hours -->
      <SettingsSection
        :title="$t('WHATSAPP_CALLS.SETTINGS.CALL_HOURS_TITLE')"
        :sub-title="$t('WHATSAPP_CALLS.SETTINGS.CALL_HOURS_DESCRIPTION')"
      >
        <div class="space-y-4 md:max-w-4xl">
          <div class="border-b border-n-weak pb-4">
            <label class="flex items-center gap-3 cursor-pointer">
              <input
                v-model="form.call_hours_enabled"
                type="checkbox"
                :class="CHECKBOX_CLASSES"
              />
              <div>
                <span class="font-medium text-n-slate-12">
                  {{ $t('WHATSAPP_CALLS.SETTINGS.CALL_HOURS_ENABLE') }}
                </span>
                <p class="text-xs text-n-slate-11 mt-0.5">
                  {{ $t('WHATSAPP_CALLS.SETTINGS.CALL_HOURS_ENABLE_HELP') }}
                </p>
              </div>
            </label>
          </div>

          <template v-if="form.call_hours_enabled">
            <div>
              <label
                class="block text-xs font-medium text-n-slate-11 uppercase tracking-wide mb-1"
              >
                {{ $t('WHATSAPP_CALLS.SETTINGS.CALL_HOURS_TIMEZONE') }}
              </label>
              <input
                v-model="form.call_hours_timezone"
                type="text"
                :class="INPUT_CLASSES"
                placeholder="America/New_York"
              />
              <p class="text-xs text-n-slate-11 mt-1">
                {{ $t('WHATSAPP_CALLS.SETTINGS.CALL_HOURS_TIMEZONE_HELP') }}
              </p>
            </div>

            <div>
              <p
                class="text-xs font-medium text-n-slate-11 uppercase tracking-wide mb-3"
              >
                {{ $t('WHATSAPP_CALLS.SETTINGS.WEEKLY_SCHEDULE') }}
              </p>
              <div class="space-y-1.5">
                <div
                  v-for="slot in form.call_hours_schedule"
                  :key="slot.day"
                  class="flex items-center gap-3 p-3 rounded-lg border border-n-weak bg-n-solid-1"
                >
                  <input
                    v-model="slot.enabled"
                    type="checkbox"
                    :class="CHECKBOX_CLASSES"
                  />
                  <span
                    class="w-28 text-sm font-medium text-n-slate-12"
                  >
                    {{
                      $t(
                        `WHATSAPP_CALLS.SETTINGS.${DAY_LABEL_KEYS[slot.day]}`
                      )
                    }}
                  </span>
                  <template v-if="slot.enabled">
                    <input
                      v-model="slot.open_time"
                      type="time"
                      :class="TIME_INPUT_CLASSES"
                    />
                    <span class="text-n-slate-9 text-sm">—</span>
                    <input
                      v-model="slot.close_time"
                      type="time"
                      :class="TIME_INPUT_CLASSES"
                    />
                  </template>
                  <span
                    v-else
                    class="inline-flex items-center px-2 py-0.5 min-h-6 text-xs font-medium rounded-md bg-n-alpha-2 text-n-slate-11"
                  >
                    {{ $t('WHATSAPP_CALLS.SETTINGS.CALL_DAY_CLOSED') }}
                  </span>
                </div>
              </div>
            </div>

          </template>
        </div>
      </SettingsSection>

      <!-- Section 4: Holiday schedule -->
      <SettingsSection
        v-if="form.call_hours_enabled"
        :title="$t('WHATSAPP_CALLS.SETTINGS.HOLIDAY_SCHEDULE')"
        :sub-title="$t('WHATSAPP_CALLS.SETTINGS.HOLIDAY_SCHEDULE_HELP')"
      >
        <div class="space-y-3 md:max-w-4xl">
          <div
            v-for="(holiday, idx) in form.call_hours_holidays"
            :key="idx"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-4"
          >
            <div class="flex items-center justify-between mb-4">
              <span
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-11"
              >
                {{ $t('WHATSAPP_CALLS.SETTINGS.HOLIDAY_SCHEDULE') }} {{ idx + 1 }}
              </span>
              <button
                type="button"
                class="text-xs font-medium text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 transition-colors"
                @click="removeHoliday(idx)"
              >
                {{ $t('WHATSAPP_CALLS.SETTINGS.REMOVE') }}
              </button>
            </div>
            <div class="grid grid-cols-3 gap-4">
              <div>
                <label
                  class="block text-xs font-medium text-n-slate-11 uppercase tracking-wide mb-1.5"
                >
                  {{ $t('WHATSAPP_CALLS.SETTINGS.HOLIDAY_DATE') }}
                </label>
                <input
                  v-model="holiday.date"
                  type="date"
                  :class="INPUT_CLASSES"
                />
              </div>
              <div>
                <label
                  class="block text-xs font-medium text-n-slate-11 uppercase tracking-wide mb-1.5"
                >
                  {{ $t('WHATSAPP_CALLS.SETTINGS.HOLIDAY_START') }}
                </label>
                <input
                  v-model="holiday.start_time"
                  type="time"
                  :class="INPUT_CLASSES"
                />
              </div>
              <div>
                <label
                  class="block text-xs font-medium text-n-slate-11 uppercase tracking-wide mb-1.5"
                >
                  {{ $t('WHATSAPP_CALLS.SETTINGS.HOLIDAY_END') }}
                </label>
                <input
                  v-model="holiday.end_time"
                  type="time"
                  :class="INPUT_CLASSES"
                />
              </div>
            </div>
          </div>

          <button
            type="button"
            class="text-sm font-medium text-woot-600 hover:text-woot-700 dark:text-woot-400 dark:hover:text-woot-300 transition-colors"
            @click="addHoliday"
          >
            + {{ $t('WHATSAPP_CALLS.SETTINGS.ADD_HOLIDAY') }}
          </button>
        </div>
      </SettingsSection>
    </template>

    <!-- Actions -->
    <div class="mx-8 flex items-center gap-3 pb-8">
      <NextButton
        type="submit"
        :label="$t('WHATSAPP_CALLS.SETTINGS.SAVE')"
        :is-loading="isSaving"
        :disabled="isSaving"
      />

    </div>
  </form>
</template>
