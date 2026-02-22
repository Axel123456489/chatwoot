<script setup>
import { computed } from 'vue';
import { useMessageContext } from '../../provider.js';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { MESSAGE_VARIANTS } from '../../constants';

const props = defineProps({
  content: {
    type: String,
    required: true,
  },
});

const { variant, contentAttributes } = useMessageContext();

const formattedContent = computed(() => {
  if (variant.value === MESSAGE_VARIANTS.ACTIVITY) {
    return props.content;
  }

  // If message was sent in plain text mode, don't apply markdown formatting
  // Support both camelCase (formatMode) and snake_case (format_mode) for compatibility
  const formatMode =
    contentAttributes.value?.formatMode || contentAttributes.value?.format_mode;
  if (formatMode === 'plain') {
    // Clean any markdown hard break artifacts (space+backslash+newline or backslash+newline)
    // that might have been serialized, then convert line breaks to <br> tags
    let plainContent = props.content;
    plainContent = plainContent.replace(/ \\\n/g, '\n');
    plainContent = plainContent.replace(/\\\n/g, '\n');
    return plainContent.replace(/\n/g, '<br>');
  }

  return new MessageFormatter(props.content).formattedMessage;
});
</script>

<template>
  <span v-dompurify-html="formattedContent" class="prose prose-bubble" />
</template>
