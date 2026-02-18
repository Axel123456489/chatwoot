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
    // Array of initial files: [{ filename, blob_id, url?, content_type? }]
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
      items: [], // { name, blobId, url, contentType, isImage }
    };
  },
  mounted() {
    if (this.initialFiles && this.initialFiles.length) {
      this.items = this.initialFiles.map(f => ({
        name: f.filename,
        blobId: f.blob_id,
        url:
          f.file_url ||
          f.url ||
          `/rails/active_storage/blobs/${f.blob_id}/${f.filename}`,
        contentType: f.content_type || '',
        isImage: this.isImageFile(f.filename, f.content_type),
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
    isImageFile(filename, contentType) {
      if (contentType && contentType.startsWith('image/')) return true;
      const imageExtensions = [
        '.jpg',
        '.jpeg',
        '.png',
        '.gif',
        '.bmp',
        '.webp',
        '.svg',
      ];
      return imageExtensions.some(ext => filename.toLowerCase().endsWith(ext));
    },
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
            const url =
              res && typeof res === 'object' && 'fileUrl' in res
                ? res.fileUrl
                : `/rails/active_storage/blobs/${id}/${file.name}`;
            this.items.push({
              name: file.name,
              blobId: id,
              url,
              contentType: file.type,
              isImage: this.isImageFile(file.name, file.type),
            });
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
    openFile(item) {
      window.open(item.url, '_blank');
    },
    getFileExtension(filename) {
      const parts = filename.split('.');
      return parts.length > 1 ? parts.pop().toLowerCase() : '';
    },
    truncateFileName(filename, maxLength = 20) {
      if (filename.length <= maxLength) return filename;
      const ext = this.getFileExtension(filename);
      const base = filename.substring(0, filename.lastIndexOf('.'));
      const truncatedBase = base.substring(0, maxLength - ext.length - 3);
      return ext ? `${truncatedBase}...${ext}` : `${truncatedBase}...`;
    },
  },
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <!-- Upload Button -->
    <label
      class="inline-flex items-center gap-2 h-9 px-3 text-sm font-medium cursor-pointer rounded-lg border border-dashed transition-all duration-200"
      :class="{
        'border-n-weak bg-n-alpha-2 hover:bg-n-alpha-3 hover:border-n-strong text-n-slate-12':
          uploadState === 'idle',
        'border-n-teal-6 bg-n-teal-2 text-n-teal-11':
          uploadState === 'uploaded',
        'border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11': uploadState === 'failed',
        'border-n-weak bg-n-alpha-1 cursor-not-allowed opacity-70':
          uploadState === 'processing',
      }"
    >
      <input
        v-if="uploadState !== 'processing'"
        type="file"
        name="attachment"
        multiple
        class="hidden"
        @change="onChangeFile"
      />
      <Spinner v-if="uploadState === 'processing'" size="small" />
      <fluent-icon
        v-else-if="uploadState === 'idle'"
        icon="attach"
        size="16"
        class="flex-shrink-0"
      />
      <fluent-icon
        v-else-if="uploadState === 'uploaded'"
        icon="checkmark-circle"
        size="16"
        class="flex-shrink-0"
      />
      <fluent-icon
        v-else-if="uploadState === 'failed'"
        icon="dismiss-circle"
        size="16"
        class="flex-shrink-0"
      />
      <span class="truncate">{{ label }}</span>
    </label>

    <!-- Attachments Preview -->
    <div v-if="items.length" class="flex flex-col gap-3">
      <!-- Images Grid -->
      <div v-if="items.some(i => i.isImage)" class="flex flex-wrap gap-3">
        <div
          v-for="item in items.filter(i => i.isImage)"
          :key="item.blobId"
          class="relative group/image w-[72px] h-[72px]"
        >
          <img
            :src="item.url"
            :alt="item.name"
            class="w-full h-full object-cover rounded-xl cursor-pointer"
            @error="item.isImage = false"
            @click="openFile(item)"
          />
          <button
            type="button"
            class="absolute top-1 ltr:right-1 rtl:left-1 w-5 h-5 flex items-center justify-center rounded-md bg-n-alpha-black2 text-white opacity-0 group-hover/image:opacity-100 transition-opacity duration-150 hover:bg-n-ruby-9"
            :title="$t('GENERAL.REMOVE') || 'Eliminar'"
            @click.stop="removeItem(item.blobId)"
          >
            <fluent-icon icon="dismiss" size="12" />
          </button>
        </div>
      </div>

      <!-- Files List -->
      <div v-if="items.some(i => !i.isImage)" class="flex flex-wrap gap-2">
        <div
          v-for="item in items.filter(i => !i.isImage)"
          :key="item.blobId"
          class="inline-flex items-center h-9 min-w-0 max-w-[280px] gap-2 px-3 rounded-lg bg-n-alpha-2 dark:bg-n-solid-3 border border-n-container"
        >
          <fluent-icon
            icon="document"
            size="16"
            class="flex-shrink-0 text-n-slate-11"
          />
          <span
            class="flex-1 text-sm font-medium text-n-slate-12 truncate cursor-pointer hover:text-n-blue-text"
            :title="item.name"
            @click="openFile(item)"
          >
            {{ truncateFileName(item.name) }}
          </span>
          <button
            type="button"
            class="flex-shrink-0 w-5 h-5 flex items-center justify-center rounded text-n-slate-11 hover:text-n-ruby-9 hover:bg-n-ruby-2 transition-colors duration-150"
            :title="$t('GENERAL.REMOVE') || 'Eliminar'"
            @click="removeItem(item.blobId)"
          >
            <fluent-icon icon="dismiss" size="12" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Minimal scoped styles - most styling is done with Tailwind classes */
</style>
