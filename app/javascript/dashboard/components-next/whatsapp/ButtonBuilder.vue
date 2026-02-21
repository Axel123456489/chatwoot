<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import DashboardIcon from 'shared/components/FluentIcon/DashboardIcon.vue';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';

const props = defineProps({
  modelValue: {
    type: Array,
    default: () => [],
  },
  maxButtons: {
    type: Number,
    default: 3,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const buttons = ref([...props.modelValue]);

const buttonTypeOptions = computed(() => [
  { label: t('WHATSAPP_TEMPLATES.PICKER.BUTTONS'), value: 'quick_reply' },
  { label: t('WHATSAPP.BUTTON_BUILDER.URL_LABEL'), value: 'url' },
  { label: t('WHATSAPP.BUTTON_BUILDER.PHONE_LABEL'), value: 'phone_number' },
]);

const canAddMore = computed(() => buttons.value.length < props.maxButtons);

const addButton = () => {
  if (!canAddMore.value) return;
  buttons.value.push({
    id: `btn_${Date.now()}`,
    type: 'quick_reply',
    text: '',
    url: '',
    phone_number: '',
  });
  emit('update:modelValue', buttons.value);
};

const removeButton = index => {
  buttons.value.splice(index, 1);
  emit('update:modelValue', buttons.value);
};

const updateButton = (index, field, value) => {
  buttons.value[index][field] = value;
  emit('update:modelValue', buttons.value);
};

const getButtonIcon = type => {
  switch (type) {
    case 'url':
      return 'link';
    case 'phone_number':
      return 'call';
    default:
      return 'arrow-reply';
  }
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex items-center justify-between">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t('WHATSAPP.BUTTON_BUILDER.TITLE') }}
      </span>
      <Button
        v-if="canAddMore"
        :label="$t('WHATSAPP.BUTTON_BUILDER.ADD_BUTTON')"
        size="small"
        @click="addButton"
      >
        <template #icon>
          <DashboardIcon icon="add" size="16" />
        </template>
      </Button>
    </div>

    <div v-if="buttons.length === 0" class="text-sm text-n-slate-11">
      {{ $t('WHATSAPP.BUTTON_BUILDER.NO_BUTTONS') }}
    </div>

    <div
      v-for="(button, index) in buttons"
      :key="button.id"
      class="flex flex-col gap-2 p-3 bg-n-alpha-2 rounded-lg"
    >
      <div class="grid grid-cols-[200px_1fr_auto] gap-3 items-center">
        <div class="flex items-center gap-2">
          <DashboardIcon
            :icon="getButtonIcon(button.type)"
            size="16"
            class="text-n-slate-11"
          />
          <span class="text-sm font-medium text-n-slate-12">
            {{
              $t('WHATSAPP.BUTTON_BUILDER.BUTTON_LABEL', { index: index + 1 })
            }}
          </span>
        </div>
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('WHATSAPP.BUTTON_BUILDER.BUTTON_TEXT') }}
        </span>
        <Button icon-only link @click="removeButton(index)">
          <template #icon>
            <DashboardIcon icon="dismiss" size="16" />
          </template>
        </Button>
      </div>

      <div class="grid grid-cols-[200px_1fr] gap-3">
        <SelectMenu
          :model-value="button.type"
          :options="buttonTypeOptions"
          :label="$t('WHATSAPP.BUTTON_BUILDER.BUTTON_TYPE')"
          @update:model-value="updateButton(index, 'type', $event)"
        />

        <Input
          :model-value="button.text"
          :placeholder="$t('WHATSAPP.BUTTON_BUILDER.BUTTON_TEXT_PLACEHOLDER')"
          :maxlength="20"
          @update:model-value="updateButton(index, 'text', $event)"
        />
      </div>

      <Input
        v-if="button.type === 'url'"
        :model-value="button.url"
        :label="$t('WHATSAPP.BUTTON_BUILDER.URL_LABEL')"
        :placeholder="$t('WHATSAPP.BUTTON_BUILDER.URL_PLACEHOLDER')"
        @update:model-value="updateButton(index, 'url', $event)"
      />

      <Input
        v-if="button.type === 'phone_number'"
        :model-value="button.phone_number"
        :label="$t('WHATSAPP.BUTTON_BUILDER.PHONE_LABEL')"
        :placeholder="$t('WHATSAPP.BUTTON_BUILDER.PHONE_PLACEHOLDER')"
        @update:model-value="updateButton(index, 'phone_number', $event)"
      />
    </div>

    <div v-if="buttons.length > 0" class="text-xs text-n-slate-11">
      {{
        $t('WHATSAPP.BUTTON_BUILDER.BUTTONS_COUNT', {
          count: buttons.length,
          max: maxButtons,
        })
      }}
    </div>
  </div>
</template>
