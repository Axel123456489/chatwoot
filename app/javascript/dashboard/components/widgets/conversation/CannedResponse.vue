<script>
import { mapGetters } from 'vuex';
import MentionBox from '../mentions/MentionBox.vue';

export default {
  components: { MentionBox },
  props: {
    searchKey: {
      type: String,
      default: '',
    },
    // Permite ajustar cuántos resultados caben visibles (aprox). Por defecto 9.75rem.
    dropdownMaxHeightRem: {
      type: Number,
      default: 16, // aumentar para que quepan más de 3
    },
  },
  emits: ['replace'],
  computed: {
    ...mapGetters({
      cannedMessages: 'getCannedResponses',
    }),
    items() {
      // Filtrar SOLO por short_code cuando el usuario escribe tras '/'
      const key = (this.searchKey || '').trim().toLowerCase();
      const list = key
        ? this.cannedMessages.filter(item =>
            String(item.short_code || '')
              .toLowerCase()
              .includes(key)
          )
        : this.cannedMessages;
      return list.map(cannedMessage => ({
        label: cannedMessage.short_code,
        key: cannedMessage.short_code,
        description: cannedMessage.content,
        contentType: cannedMessage.content_type || 'markdown',
        // Prefer the new key `files`; fall back to legacy `file_base_data` for compatibility
        files: cannedMessage.files || cannedMessage.file_base_data || [],
      }));
    },
  },
  watch: {
    searchKey() {
      this.fetchCannedResponses();
    },
  },
  mounted() {
    this.fetchCannedResponses();
  },
  methods: {
    fetchCannedResponses() {
      this.$store.dispatch('getCannedResponse', { searchKey: this.searchKey });
    },
    handleMentionClick(item = {}) {
      // Emitir contenido normalizado para plain_text para evitar CRLF inconsistentes
      const normalizedContent =
        item.contentType === 'plain_text'
          ? String(item.description || '').replace(/\r\n?/g, '\n')
          : item.description;

      this.$emit('replace', normalizedContent, item.files, item.contentType);
    },
    hasAttachments(item = {}) {
      return Array.isArray(item.files) && item.files.length > 0;
    },
    extensionFor(file = {}) {
      // 1) Try from filename
      let ext = '';
      if (file.filename && typeof file.filename === 'string') {
        const parts = file.filename.split('.');
        if (parts.length > 1) {
          ext = parts.pop();
        }
      }
      // 2) Fallback to content-type subtype
      if (!ext && file.file_type && typeof file.file_type === 'string') {
        const typeParts = file.file_type.split('/');
        if (typeParts.length > 1) {
          ext = typeParts[1];
        }
      }
      if (!ext) return null;
      ext = String(ext).toUpperCase();
      // Normalize common cases
      if (ext === 'JPEG') ext = 'JPG';
      return ext;
    },
    attachmentTypes(item = {}) {
      if (!this.hasAttachments(item)) return '';
      const uniqueExts = [
        ...new Set((item.files || []).map(this.extensionFor).filter(Boolean)),
      ];
      if (uniqueExts.length <= 2) return uniqueExts.join(', ');
      return `${uniqueExts.slice(0, 2).join(', ')} +${uniqueExts.length - 2}`;
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <MentionBox
    v-if="items.length"
    :items="items"
    :max-height-rem="dropdownMaxHeightRem"
    @mention-select="handleMentionClick"
  >
    <template #default="{ item, selected }">
      <p
        class="max-w-full min-w-0 mb-0 overflow-hidden text-sm font-medium text-n-slate-11 group-hover:text-n-slate-12 text-ellipsis whitespace-nowrap"
        :class="{ 'text-n-slate-12': selected }"
      >
        {{ item.description }}
      </p>
      <p
        class="max-w-full min-w-0 mb-0 overflow-hidden text-xs text-n-slate-11 group-hover:text-n-slate-12 text-ellipsis whitespace-nowrap flex items-center gap-2"
        :class="{ 'text-n-slate-12': selected }"
      >
        <span>/{{ item.label }}</span>
        <template v-if="hasAttachments(item)">
          <span class="inline-flex items-center gap-1">
            <i class="i-ph-paperclip text-[0.9em]" />
            <span class="uppercase">{{ attachmentTypes(item) }}</span>
          </span>
        </template>
      </p>
    </template>
  </MentionBox>
</template>
