<script setup>
const emit = defineEmits(['select']);

const commonReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

const handleSelect = emoji => {
  emit('select', emoji);
};
</script>

<template>
  <div
    class="reaction-picker flex gap-1 p-2 bg-n-background rounded-lg shadow-lg border border-n-weak"
    @click.stop
    @mousedown.stop
  >
    <button
      v-for="emoji in commonReactions"
      :key="emoji"
      type="button"
      class="w-8 h-8 flex items-center justify-center rounded hover:bg-n-alpha-2 transition-colors text-lg cursor-pointer"
      @click.stop="handleSelect(emoji)"
      @mousedown.stop
    >
      {{ emoji }}
    </button>
  </div>
</template>

<style scoped>
.reaction-picker {
  animation: fadeIn 0.15s ease-out;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: scale(0.95);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}
</style>
