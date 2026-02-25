<script setup>
import { computed, ref } from 'vue';
import BaseBubble from 'next/message/bubbles/Base.vue';
import FormattedContent from './FormattedContent.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import DashboardIcon from 'shared/components/FluentIcon/DashboardIcon.vue';
import ButtonReplyBadge from 'dashboard/components-next/message/badges/ButtonReplyBadge.vue';
import { MESSAGE_TYPES, MESSAGE_VARIANTS } from '../../constants';
import { useMessageContext } from '../../provider.js';
import { useTranslations } from 'dashboard/composables/useTranslations';

const { content, attachments, contentAttributes, messageType, variant } =
  useMessageContext();

const { hasTranslations, translationContent } =
  useTranslations(contentAttributes);

const renderOriginal = ref(false);

const whatsappButtons = computed(() => {
  return contentAttributes.value?.whatsappButtons || [];
});

const interactiveType = computed(() => {
  return contentAttributes.value?.whatsappInteractiveType || '';
});

const hasButtons = computed(() => {
  return whatsappButtons.value.length > 0;
});

const renderContent = computed(() => {
  if (renderOriginal.value) {
    return content.value;
  }

  if (hasTranslations.value) {
    return translationContent.value;
  }

  return content.value;
});

const isTemplate = computed(() => {
  return messageType.value === MESSAGE_TYPES.TEMPLATE;
});

const isEmpty = computed(() => {
  return !content.value && !attachments.value?.length;
});

const handleSeeOriginal = () => {
  renderOriginal.value = !renderOriginal.value;
};

const handleButtonClick = button => {
  if (button.url) {
    window.open(button.url, '_blank', 'noopener,noreferrer');
  } else if (button.phone_number) {
    window.location.href = `tel:${button.phone_number}`;
  }
};

const buttonClass = computed(() => {
  if (variant.value === MESSAGE_VARIANTS.ERROR) {
    return 'px-3 py-2 flex items-center justify-center gap-2 cursor-pointer bg-n-ruby-4 border border-n-ruby-6 text-n-ruby-12 rounded-xl hover:bg-n-ruby-5 transition-colors font-medium text-sm';
  }
  return 'px-3 py-2 flex items-center justify-center gap-2 cursor-pointer bg-n-solid-blue text-n-slate-12 rounded-xl hover:opacity-90 transition-opacity font-medium text-sm';
});
</script>

<template>
  <div class="flex flex-col gap-1">
    <BaseBubble class="px-4 py-3" data-bubble-name="text">
      <div class="gap-3 flex flex-col">
        <span v-if="isEmpty" class="text-n-slate-11">
          {{ $t('CONVERSATION.NO_CONTENT') }}
        </span>
        <ButtonReplyBadge :content-attributes="contentAttributes" />
        <FormattedContent v-if="renderContent" :content="renderContent" />
        <TranslationToggle
          v-if="hasTranslations"
          class="-mt-3"
          :showing-original="renderOriginal"
          @toggle="handleSeeOriginal"
        />
        <AttachmentChips :attachments="attachments" class="gap-2" />
        <template v-if="isTemplate">
          <div
            v-if="contentAttributes.submittedEmail"
            class="px-2 py-1 rounded-lg bg-n-alpha-3"
          >
            {{ contentAttributes.submittedEmail }}
          </div>
        </template>
      </div>
    </BaseBubble>

    <!-- WhatsApp Interactive Buttons - OUTSIDE the bubble -->
    <div
      v-if="hasButtons && interactiveType === 'cta'"
      class="flex flex-col gap-1"
    >
      <div
        v-for="(button, index) in whatsappButtons"
        :key="index"
        :class="buttonClass"
        @click="handleButtonClick(button)"
      >
        <DashboardIcon
          v-if="button.type === 'phone_number'"
          icon="call"
          size="16"
        />
        <DashboardIcon
          v-else-if="button.type === 'url'"
          icon="link"
          size="16"
        />
        <span>{{ button.text }}</span>
      </div>
    </div>

    <div
      v-if="hasButtons && interactiveType === 'quick_reply'"
      class="flex flex-col gap-1"
    >
      <div
        v-for="(button, index) in whatsappButtons"
        :key="index"
        :class="buttonClass"
      >
        <svg
          width="15"
          height="15"
          viewBox="0 0 15 15"
          fill="none"
          class="stroke-current"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            d="M.667 6.654 5.315.667v3.326c7.968 0 8.878 6.46 8.656 10.007l-.005-.027c-.334-1.79-.474-4.658-8.65-4.658v3.327z"
            stroke-width="1.333"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
        <span>{{ button.text }}</span>
      </div>
    </div>
  </div>
</template>

<style>
p:last-child {
  margin-bottom: 0;
}
</style>
