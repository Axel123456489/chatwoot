<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from './provider.js';

const { t } = useI18n();
const { contentAttributes } = useMessageContext();

const reactions = computed(() => {
  const reactionData = contentAttributes.value?.reactions;
  if (!reactionData || typeof reactionData !== 'object') return [];

  return Object.entries(reactionData).map(([id, value]) => ({
    id,
    emoji: value.emoji,
    timestamp: value.timestamp,
    userType: value.user_type,
    userName: value.user_name,
  }));
});

const hasReactions = computed(() => reactions.value.length > 0);

// Group reactions by emoji with user info
const groupedReactions = computed(() => {
  const groups = {};
  reactions.value.forEach(reaction => {
    if (!groups[reaction.emoji]) {
      groups[reaction.emoji] = {
        emoji: reaction.emoji,
        count: 0,
        users: [],
        hasAgent: false,
        hasCustomer: false,
      };
    }
    groups[reaction.emoji].count += 1;
    if (reaction.userName) {
      groups[reaction.emoji].users.push(reaction.userName);
    }
    if (reaction.userType === 'agent') {
      groups[reaction.emoji].hasAgent = true;
    } else {
      groups[reaction.emoji].hasCustomer = true;
    }
  });
  return Object.values(groups);
});

const getTooltip = reaction => {
  if (reaction.users.length > 0) {
    return reaction.users.join(', ');
  }
  return reaction.hasCustomer ? t('CONVERSATION.CUSTOMER_REACTION') : '';
};
</script>

<template>
  <div v-if="hasReactions" class="flex gap-1 mt-1 flex-wrap">
    <span
      v-for="reaction in groupedReactions"
      :key="reaction.emoji"
      class="inline-flex items-center px-1.5 py-0.5 rounded-full text-xs cursor-default"
      :class="reaction.hasAgent ? 'bg-n-blue-3' : 'bg-n-alpha-2'"
      :title="getTooltip(reaction)"
    >
      <span class="text-sm">{{ reaction.emoji }}</span>
      <span v-if="reaction.count > 1" class="ml-1 text-n-slate-11">
        {{ reaction.count }}
      </span>
    </span>
  </div>
</template>
