<script>
import { useAlert } from 'dashboard/composables';
import Spinner from 'shared/components/Spinner.vue';
export default {
  components: {
    Spinner,
  },
  props: {
    // v-model value: array of blob ids
    modelValue: {
      type: Array,
      default: () => [],
    },
    // Array of initial files: [{ filename, blob_id }]
    initialFiles: {
      type: Array,
      default: () => [],
    },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      uploadState: 'idle',
      label: this.$t('AUTOMATION.ATTACHMENT.LABEL_IDLE'),
      // local list of items to render names alongside blob ids
      items: [], // { name, blobId }
    };
  },
  mounted() {
    if (this.initialFiles && this.initialFiles.length) {
      this.items = this.initialFiles.map(f => ({
        name: f.filename,
        blobId: f.blob_id,
      }));
      // emit initial ids to ensure parent has the same selection if not already provided
      if (!this.modelValue || !this.modelValue.length) {
        this.$emit(
          'update:modelValue',
          this.items.map(i => i.blobId)
        );
      }
      this.uploadState = 'uploaded';
      this.label = this.$t('AUTOMATION.ATTACHMENT.LABEL_UPLOADED');
    }
  },
  methods: {
    async onChangeFile(event) {
      const files = Array.from(event.target.files || []);
      if (!files.length) return;
      this.uploadState = 'processing';
      this.label = this.$t('AUTOMATION.ATTACHMENT.LABEL_UPLOADING');
      try {
        const uploadedIds = await Promise.all(
          files.map(async file => {
            const res = await this.$store.dispatch(
              'automations/uploadAttachment',
              file
            );
            const id =
              res && typeof res === 'object' && 'blobId' in res
                ? res.blobId
                : res;
            this.items.push({ name: file.name, blobId: id });
            return id;
          })
        );
        const uniqueIds = Array.from(
          new Set([...(this.modelValue || []), ...uploadedIds])
        );
        this.$emit('update:modelValue', uniqueIds);
        this.uploadState = 'uploaded';
        this.label = this.$t('AUTOMATION.ATTACHMENT.LABEL_UPLOADED');
        // Reset file input so same file can be selected again if needed
        event.target.value = '';
      } catch (error) {
        this.uploadState = 'failed';
        this.label = this.$t('AUTOMATION.ATTACHMENT.LABEL_UPLOAD_FAILED');
        useAlert(this.$t('AUTOMATION.ATTACHMENT.UPLOAD_ERROR'));
      }
    },
    removeItem(blobId) {
      this.items = this.items.filter(i => i.blobId !== blobId);
      const remaining = (this.modelValue || []).filter(id => id !== blobId);
      this.$emit('update:modelValue', remaining);
      if (!remaining.length) {
        this.uploadState = 'idle';
        this.label = this.$t('AUTOMATION.ATTACHMENT.LABEL_IDLE');
      }
    },
  },
};
</script>

<template>
  <div>
    <label class="input-wrapper" :class="uploadState">
      <input
        v-if="uploadState !== 'processing'"
        type="file"
        name="attachment"
        multiple
        :class="uploadState === 'processing' ? 'disabled' : ''"
        @change="onChangeFile"
      />
      <Spinner v-if="uploadState === 'processing'" />
      <fluent-icon v-if="uploadState === 'idle'" icon="file-upload" />
      <fluent-icon
        v-if="uploadState === 'uploaded'"
        icon="checkmark-circle"
        type="outline"
        class="success-icon"
      />
      <fluent-icon
        v-if="uploadState === 'failed'"
        icon="dismiss-circle"
        type="outline"
        class="error-icon"
      />
      <p class="file-button">{{ label }}</p>
    </label>

    <ul v-if="items.length" class="mt-2 space-y-1">
      <li
        v-for="i in items"
        :key="i.blobId"
        class="flex items-center justify-between text-xs"
      >
        <span class="truncate">{{ i.name }}</span>
        <button
          type="button"
          class="text-n-ruby-9 hover:underline"
          @click="removeItem(i.blobId)"
        >
          {{ $t('GENERAL.REMOVE') || 'Remove' }}
        </button>
      </li>
    </ul>
  </div>
</template>

<style scoped>
input[type='file'] {
  @apply hidden;
}
.input-wrapper {
  @apply flex h-9 bg-n-background py-1 px-2 items-center text-xs cursor-pointer rounded-sm border border-dashed border-n-strong;
}
.success-icon {
  @apply text-n-teal-9 mr-2;
}
.error-icon {
  @apply text-n-ruby-9 mr-2;
}

.processing {
  @apply cursor-not-allowed opacity-90;
}
.file-button {
  @apply whitespace-nowrap overflow-hidden text-ellipsis w-full mb-0;
}
</style>
