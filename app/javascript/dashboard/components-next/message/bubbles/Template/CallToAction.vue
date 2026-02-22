<script setup>
import { computed } from 'vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
});

const buttons = computed(() => {
  return props.message.contentAttributes?.whatsappButtons || [];
});

const handleButtonClick = button => {
  if (button.url) {
    window.open(button.url, '_blank', 'noopener,noreferrer');
  } else if (button.phone_number) {
    window.location.href = `tel:${button.phone_number}`;
  }
};
</script>

<template>
  <div class="text-n-slate-12 max-w-80 flex flex-col gap-2">
    <div class="p-3 bg-n-alpha-2 rounded-xl">
      <span
        v-dompurify-html="message.content"
        class="prose prose-bubble font-medium text-sm"
      />
    </div>
    <div
      v-for="(button, index) in buttons"
      :key="index"
      class="px-3 py-2 flex items-center justify-center gap-2 cursor-pointer border border-n-strong rounded-lg hover:bg-n-alpha-2 transition-colors text-n-blue-11 font-medium text-sm"
      @click="handleButtonClick(button)"
    >
      <FluentIcon v-if="button.type === 'phone_number'" icon="call" size="16" />
      <FluentIcon v-else-if="button.type === 'url'" icon="link" size="16" />
      <svg
        v-else
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
</template>
