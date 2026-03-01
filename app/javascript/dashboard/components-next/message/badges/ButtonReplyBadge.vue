<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';

const props = defineProps({
  contentAttributes: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();

const isButtonReply = computed(() => {
  return props.contentAttributes?.fromButton === true;
});

const buttonType = computed(() => {
  return props.contentAttributes?.buttonType || 'button_reply';
});

const buttonLabel = computed(() => {
  const type = buttonType.value;
  if (type === 'list_reply') {
    return t('CONVERSATION.BUTTON_REPLY.LIST_REPLY');
  }
  if (type === 'template_button') {
    return t('CONVERSATION.BUTTON_REPLY.TEMPLATE_BUTTON');
  }
  return t('CONVERSATION.BUTTON_REPLY.BUTTON_REPLY');
});

const buttonTitle = computed(() => {
  return (
    props.contentAttributes?.buttonTitle ||
    props.contentAttributes?.buttonText ||
    ''
  );
});
</script>

<template>
  <div
    v-if="isButtonReply"
    class="inline-flex items-center gap-1.5 px-2 py-1 bg-n-blue-alpha-2 rounded-md text-xs font-medium text-n-blue-11 mb-2"
  >
    <FluentIcon icon="cursor-click" size="12" />
    <span>{{ buttonLabel }}</span>
    <span v-if="buttonTitle" class="text-n-slate-11">
      {{ ` · ${buttonTitle}` }}
    </span>
  </div>
</template>
