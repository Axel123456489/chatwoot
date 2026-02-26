<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import MultiSelect from './MultiSelect.vue';

const { options } = defineProps({
  options: {
    type: Array,
    required: true,
  },
});

const { t } = useI18n();

const model = defineModel({
  type: Object,
  default: () => ({ from: [], to: [] }),
});

const fromValue = computed({
  get: () => (Array.isArray(model.value?.from) ? model.value.from : []),
  set: val => {
    model.value = { ...model.value, from: val };
  },
});

const toValue = computed({
  get: () => (Array.isArray(model.value?.to) ? model.value.to : []),
  set: val => {
    model.value = { ...model.value, to: val };
  },
});
</script>

<template>
  <div class="flex items-center gap-1">
    <span class="text-xs text-n-slate-11 shrink-0">
      {{ t('FILTER.ATTRIBUTE_CHANGED.FROM') }}
    </span>
    <MultiSelect v-model="fromValue" :options="options" :max-chips="2" />
    <span class="text-xs text-n-slate-11 shrink-0">
      {{ t('FILTER.ATTRIBUTE_CHANGED.TO') }}
    </span>
    <MultiSelect v-model="toValue" :options="options" :max-chips="2" />
  </div>
</template>
