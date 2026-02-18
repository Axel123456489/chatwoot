<script setup>
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import { createTemplate, updateTemplate } from './helpers/templatesHelper';

const props = defineProps({
  inboxes: {
    type: Array,
    required: true,
  },
  initialInbox: {
    type: Object,
    default: null,
  },
  // Modo edición
  mode: {
    type: String,
    default: 'create', // 'create' | 'edit'
  },
  templateToEdit: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['close', 'created']);

const { t } = useI18n();

// Form data
const templateName = ref('');
const selectedInbox = ref(null);
const selectedLanguage = ref('en');
const selectedCategory = ref('UTILITY');
const headerType = ref('none');
const headerText = ref('');
const bodyText = ref('');
const footerText = ref('');
const buttons = ref([]);
const isLoading = ref(false);

const languageOptions = computed(() => [
  {
    value: 'en',
    label: t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.LANGUAGE.OPTIONS.ENGLISH'),
  },
  {
    value: 'es',
    label: t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.LANGUAGE.OPTIONS.SPANISH'),
  },
  {
    value: 'pt_BR',
    label: t(
      'SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.LANGUAGE.OPTIONS.PORTUGUESE_BRAZIL'
    ),
  },
  {
    value: 'fr',
    label: t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.LANGUAGE.OPTIONS.FRENCH'),
  },
  {
    value: 'de',
    label: t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.LANGUAGE.OPTIONS.GERMAN'),
  },
]);

const categoryOptions = computed(() => [
  {
    value: 'UTILITY',
    label: t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.CATEGORY.OPTIONS.UTILITY'),
  },
  {
    value: 'MARKETING',
    label: t(
      'SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.CATEGORY.OPTIONS.MARKETING'
    ),
  },
  {
    value: 'AUTHENTICATION',
    label: t(
      'SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.CATEGORY.OPTIONS.AUTHENTICATION'
    ),
  },
]);

const headerTypeOptions = computed(() => [
  {
    value: 'none',
    label: t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.HEADER.OPTION_NONE'),
  },
  {
    value: 'text',
    label: t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.HEADER.OPTION_TEXT'),
  },
]);

const headerTitle = computed(() =>
  props.mode === 'edit'
    ? t('SETTINGS.TEMPLATES.CREATE_MODAL.HEADER.TITLE_EDIT')
    : t('SETTINGS.TEMPLATES.CREATE_MODAL.HEADER.TITLE_CREATE')
);

const headerSubtitle = computed(() =>
  props.mode === 'edit'
    ? t('SETTINGS.TEMPLATES.CREATE_MODAL.HEADER.SUBTITLE_EDIT')
    : t('SETTINGS.TEMPLATES.CREATE_MODAL.HEADER.SUBTITLE_CREATE')
);

const submitButtonLabel = computed(() =>
  props.mode === 'edit'
    ? t('SETTINGS.TEMPLATES.CREATE_MODAL.BUTTONS.SAVE_CHANGES')
    : t('SETTINGS.TEMPLATES.CREATE_MODAL.BUTTONS.SUBMIT_FOR_APPROVAL')
);

const buttonPlaceholder = index =>
  t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.BUTTONS.PLACEHOLDER', {
    index: index + 1,
  });

const inboxOptionLabel = inbox => {
  if (!inbox) return '';
  if (!inbox.phone_number) {
    return inbox.name || '';
  }
  return t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.INBOX.OPTION_WITH_PHONE', {
    name: inbox.name,
    phone: inbox.phone_number,
  });
};

// Helpers
const sanitizeTemplateName = raw => {
  if (!raw) return '';
  let v = String(raw)
    .toLowerCase()
    .replace(/\s+/g, '_') // spaces to underscores
    .replace(/[^a-z0-9_]/g, '') // only a-z, 0-9 and _
    .replace(/_+/g, '_') // collapse multiple underscores
    .replace(/^_+|_+$/g, ''); // trim leading/trailing underscores
  return v;
};

const onTemplateNameInput = e => {
  templateName.value = sanitizeTemplateName(e.target.value);
};

// Form validation
const validationRules = {
  templateName: {
    required,
    minLength: minLength(1),
  },
  selectedInbox: {
    required,
  },
  bodyText: {
    required,
    minLength: minLength(1),
  },
};

const v$ = useVuelidate(validationRules, {
  templateName,
  selectedInbox,
  bodyText,
});

// Computed
const isFormValid = computed(() => {
  return (
    !v$.value.$invalid &&
    templateName.value.trim().length > 0 &&
    bodyText.value.trim().length > 0 &&
    selectedInbox.value
  );
});

const characterCount = computed(() => bodyText.value.length);

const sampleVariableTokens = Object.freeze({
  first: '{{1}}',
  second: '{{2}}',
});

// Methods
const addButton = () => {
  if (buttons.value.length < 3) {
    buttons.value.push({
      type: 'QUICK_REPLY',
      text: '',
    });
  }
};

const removeButton = index => {
  buttons.value.splice(index, 1);
};

const handleSubmit = async () => {
  if (!isFormValid.value) return;

  isLoading.value = true;
  try {
    const sanitizedName = sanitizeTemplateName(templateName.value);

    // Detect variables in body_text like {{1}}, {{2}}, ... and create example placeholders
    const placeholderRegex = /\{\{\s*(\d+)\s*\}\}/g;
    const indices = Array.from(
      new Set(
        (bodyText.value.match(placeholderRegex) || []).map(m =>
          Number(m.replace(/[^0-9]/g, ''))
        )
      )
    ).sort((a, b) => a - b);
    const variablesExamples = indices.map(idx => `example_${idx}`);

    // Build base data (fields that can change in edit mode)
    const baseData = {
      header_type: headerType.value !== 'none' ? headerType.value : null,
      header_text: headerType.value === 'text' ? headerText.value : null,
      body_text: bodyText.value.trim(),
      footer_text: footerText.value.trim() || null,
      buttons: buttons.value.filter(btn => btn.text.trim()),
      variables: variablesExamples,
    };

    // In edit mode, do NOT send name/language/category to avoid overriding existing values server-side
    const templateData =
      props.mode === 'edit' && props.templateToEdit?.id
        ? { ...baseData }
        : {
            name: sanitizedName,
            language: selectedLanguage.value,
            category: selectedCategory.value,
            inbox_id: selectedInbox.value.id,
            ...baseData,
          };

    if (props.mode === 'edit' && props.templateToEdit?.id) {
      await updateTemplate(
        selectedInbox.value.id,
        props.templateToEdit.id,
        templateData
      );
      useAlert(t('SETTINGS.TEMPLATES.CREATE_MODAL.MESSAGES.UPDATE_SUCCESS'));
    } else {
      await createTemplate(templateData, selectedInbox.value.id);
      useAlert(t('SETTINGS.TEMPLATES.CREATE_MODAL.MESSAGES.CREATE_SUCCESS'));
    }
    emit('created');
    emit('close');
  } catch (error) {
    const message =
      error?.response?.data?.error ||
      error?.message ||
      t('SETTINGS.TEMPLATES.CREATE_MODAL.MESSAGES.ERROR_GENERIC');
    useAlert(message);
  } finally {
    isLoading.value = false;
  }
};

const onClose = () => {
  emit('close');
};

// Watchers
// Removed watcher to avoid unintended reassignments of selectedInbox when adding/editing content inside the form

// Prefer parent-provided initial inbox if present; otherwise auto-select if only one available
if (props.initialInbox) {
  selectedInbox.value = props.initialInbox;
} else if (props.inboxes.length === 1) {
  selectedInbox.value = props.inboxes[0];
}

// Prefill cuando se edita
if (props.mode === 'edit' && props.templateToEdit) {
  const templateRecord = props.templateToEdit;
  templateName.value = sanitizeTemplateName(templateRecord.name || '');
  if (templateRecord.language) selectedLanguage.value = templateRecord.language;
  if (templateRecord.category)
    selectedCategory.value = String(templateRecord.category).toUpperCase();
  if (templateRecord.inbox_id && Array.isArray(props.inboxes)) {
    const inboxMatch = props.inboxes.find(
      inbox => inbox.id === templateRecord.inbox_id
    );
    if (inboxMatch) selectedInbox.value = inboxMatch;
  }
  const components = Array.isArray(templateRecord.components)
    ? templateRecord.components
    : [];
  const header = components.find(
    c => c.type === 'HEADER' && (c.text || c.format === 'TEXT')
  );
  const body = components.find(c => c.type === 'BODY' && c.text);
  const footer = components.find(c => c.type === 'FOOTER' && c.text);
  const buttonsComp = components.find(
    c => Array.isArray(c.buttons) && c.buttons.length
  );
  headerType.value = header && header.text ? 'text' : 'none';
  headerText.value = header && header.text ? header.text : '';
  if (body && body.text) bodyText.value = body.text;
  if (footer && footer.text) footerText.value = footer.text;
  if (buttonsComp) {
    buttons.value = buttonsComp.buttons
      .filter(b => b.type === 'QUICK_REPLY' || !b.type)
      .slice(0, 3)
      .map(b => ({ type: 'QUICK_REPLY', text: b.text || '' }));
  }
}
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto max-w-2xl w-full">
    <woot-modal-header
      :header-title="headerTitle"
      :header-content="headerSubtitle"
    />

    <form
      class="flex flex-col w-full p-6 space-y-6"
      @submit.prevent="handleSubmit"
    >
      <div class="w-full">
        <label class="block text-sm font-medium text-n-slate-12 mb-2">
          {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.NAME.LABEL') }}
        </label>
        <input
          :value="templateName"
          type="text"
          :placeholder="
            t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.NAME.PLACEHOLDER')
          "
          :disabled="props.mode === 'edit'"
          class="w-full px-3 py-2 border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-blue-5 focus:border-n-blue-5"
          :class="{ 'border-red-500': v$.templateName.$error }"
          @input="onTemplateNameInput"
          @blur="v$.templateName.$touch"
        />
        <p class="text-xs text-n-slate-9 mt-1">
          {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.NAME.HELP') }}
        </p>
        <span v-if="v$.templateName.$error" class="text-xs text-red-500 mt-1">
          {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.NAME.ERROR') }}
        </span>
      </div>

      <div class="w-full">
        <label class="block text-sm font-medium text-n-slate-12 mb-2">
          {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.INBOX.LABEL') }}
        </label>
        <select
          v-model="selectedInbox"
          class="w-full px-3 py-2 border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-5 focus:border-n-blue-5"
          :class="{ 'border-red-500': v$.selectedInbox.$error }"
          @blur="v$.selectedInbox.$touch"
        >
          <option :value="null">
            {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.INBOX.PLACEHOLDER') }}
          </option>
          <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox">
            {{ inboxOptionLabel(inbox) }}
          </option>
        </select>
        <span v-if="v$.selectedInbox.$error" class="text-xs text-red-500 mt-1">
          {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.INBOX.ERROR') }}
        </span>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-2">
            {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.LANGUAGE.LABEL') }}
          </label>
          <select
            v-model="selectedLanguage"
            class="w-full px-3 py-2 border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-5 focus:border-n-blue-5"
            :disabled="props.mode === 'edit'"
          >
            <option
              v-for="language in languageOptions"
              :key="language.value"
              :value="language.value"
            >
              {{ language.label }}
            </option>
          </select>
        </div>

        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-2">
            {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.CATEGORY.LABEL') }}
          </label>
          <select
            v-model="selectedCategory"
            class="w-full px-3 py-2 border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-5 focus:border-n-blue-5"
            :disabled="props.mode === 'edit'"
          >
            <option
              v-for="category in categoryOptions"
              :key="category.value"
              :value="category.value"
            >
              {{ category.label }}
            </option>
          </select>
        </div>
      </div>

      <div class="w-full">
        <label class="block text-sm font-medium text-n-slate-12 mb-2">
          {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.HEADER.LABEL') }}
        </label>
        <select
          v-model="headerType"
          class="w-full px-3 py-2 border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-5 focus:border-n-blue-5 mb-3"
        >
          <option
            v-for="option in headerTypeOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>

        <input
          v-if="headerType === 'text'"
          v-model="headerText"
          type="text"
          :placeholder="
            t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.HEADER.PLACEHOLDER')
          "
          maxlength="60"
          class="w-full px-3 py-2 border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-blue-5 focus:border-n-blue-5"
        />
      </div>

      <div class="w-full">
        <label class="block text-sm font-medium text-n-slate-12 mb-2">
          {{
            t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.BODY.LABEL', {
              count: characterCount,
              limit: 1024,
            })
          }}
        </label>
        <textarea
          v-model="bodyText"
          rows="4"
          maxlength="1024"
          :placeholder="
            t(
              'SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.BODY.PLACEHOLDER',
              sampleVariableTokens
            )
          "
          class="w-full px-3 py-2 border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-blue-5 focus:border-n-blue-5 resize-y"
          :class="{ 'border-red-500': v$.bodyText.$error }"
          @blur="v$.bodyText.$touch"
        />
        <p class="text-xs text-n-slate-9 mt-1">
          {{
            t(
              'SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.BODY.VARIABLE_HINT',
              sampleVariableTokens
            )
          }}
        </p>
        <span v-if="v$.bodyText.$error" class="text-xs text-red-500 mt-1">
          {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.BODY.ERROR') }}
        </span>
      </div>

      <div class="w-full">
        <label class="block text-sm font-medium text-n-slate-12 mb-2">
          {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.FOOTER.LABEL') }}
        </label>
        <input
          v-model="footerText"
          type="text"
          :placeholder="
            t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.FOOTER.PLACEHOLDER')
          "
          maxlength="60"
          class="w-full px-3 py-2 border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-blue-5 focus:border-n-blue-5"
        />
      </div>

      <div class="w-full">
        <div class="flex items-center justify-between mb-2">
          <label class="block text-sm font-medium text-n-slate-12">
            {{ t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.BUTTONS.LABEL') }}
          </label>
          <Button
            v-if="buttons.length < 3"
            type="button"
            icon="i-lucide-plus"
            slate
            xs
            :label="t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.BUTTONS.ADD')"
            @click="addButton"
          />
        </div>

        <div v-if="buttons.length > 0" class="space-y-2">
          <div
            v-for="(button, index) in buttons"
            :key="index"
            class="flex items-center gap-2"
          >
            <input
              v-model="button.text"
              type="text"
              :placeholder="buttonPlaceholder(index)"
              maxlength="20"
              class="flex-1 px-3 py-2 border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-blue-5 focus:border-n-blue-5"
            />
            <Button
              type="button"
              icon="i-lucide-trash-2"
              ruby
              xs
              faded
              @click="removeButton(index)"
            />
          </div>
        </div>
      </div>

      <div class="flex flex-row justify-end w-full gap-3 pt-4">
        <Button
          type="button"
          faded
          slate
          :label="t('SETTINGS.TEMPLATES.ACTIONS.CANCEL')"
          @click="onClose"
        />
        <Button
          type="submit"
          :label="submitButtonLabel"
          :disabled="!isFormValid || isLoading"
          :is-loading="isLoading"
        />
      </div>
    </form>
  </div>
</template>
