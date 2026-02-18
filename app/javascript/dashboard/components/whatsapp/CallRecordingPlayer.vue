<script>
import Spinner from 'shared/components/Spinner.vue';

export default {
  name: 'CallRecordingPlayer',
  components: {
    Spinner,
  },
  props: {
    recordingUrl: {
      type: String,
      required: true,
    },
    callId: {
      type: [String, Number],
      required: true,
    },
  },
  data() {
    return {
      isLoading: true,
      hasError: false,
      isPlaying: false,
      currentTime: 0,
      duration: 0,
      seekPosition: 0,
      volume: 0.8,
      isMuted: false,
      playbackSpeed: 1.0,
      audioContext: null,
      analyser: null,
      audioData: null,
      waveformData: [],
    };
  },
  computed: {
    progressPercentage() {
      if (this.duration === 0) return 0;
      return (this.currentTime / this.duration) * 100;
    },
    volumeIcon() {
      if (this.isMuted || this.volume === 0) return 'speaker-mute';
      if (this.volume < 0.5) return 'speaker-1';
      return 'speaker-2';
    },
    timeMarkers() {
      if (this.duration === 0) return [];

      const markers = [];
      const interval = Math.ceil(this.duration / 5); // 5 markers

      for (let i = 0; i <= this.duration; i += interval) {
        markers.push({ time: i });
      }

      return markers;
    },
  },
  mounted() {
    this.loadRecording();
  },
  beforeUnmount() {
    this.cleanup();
  },
  methods: {
    async loadRecording() {
      this.isLoading = true;
      this.hasError = false;

      try {
        // Create audio context for waveform visualization
        this.audioContext = new (window.AudioContext ||
          window.webkitAudioContext)();

        // Load audio data
        const response = await fetch(this.recordingUrl);
        const arrayBuffer = await response.arrayBuffer();
        const audioBuffer =
          await this.audioContext.decodeAudioData(arrayBuffer);

        // Generate waveform data
        this.generateWaveformData(audioBuffer);

        // Draw waveform
        this.$nextTick(() => {
          this.drawWaveform();
        });

        this.isLoading = false;
      } catch (error) {
        this.hasError = true;
        this.isLoading = false;
      }
    },

    generateWaveformData(audioBuffer) {
      const rawData = audioBuffer.getChannelData(0);
      const samples = 200; // Number of bars in waveform
      const blockSize = Math.floor(rawData.length / samples);
      const waveformData = [];

      for (let i = 0; i < samples; i += 1) {
        const start = i * blockSize;
        let sum = 0;

        for (let j = 0; j < blockSize; j += 1) {
          sum += Math.abs(rawData[start + j]);
        }

        waveformData.push(sum / blockSize);
      }

      // Normalize data
      const max = Math.max(...waveformData);
      this.waveformData = waveformData.map(value => value / max);
    },

    drawWaveform() {
      const canvas = this.$refs.waveformCanvas;
      if (!canvas) return;

      const ctx = canvas.getContext('2d');
      const width = canvas.offsetWidth;
      const height = canvas.offsetHeight;

      // Set canvas size
      canvas.width = width;
      canvas.height = height;

      // Clear canvas
      ctx.clearRect(0, 0, width, height);

      // Calculate bar width and spacing
      const barCount = this.waveformData.length;
      const barWidth = (width / barCount) * 0.8;
      const barSpacing = (width / barCount) * 0.2;

      // Draw waveform bars
      this.waveformData.forEach((value, index) => {
        const barHeight = value * height * 0.8;
        const x = index * (barWidth + barSpacing);
        const y = (height - barHeight) / 2;

        // Determine color based on progress
        const progressIndex = Math.floor(
          (this.currentTime / this.duration) * barCount
        );
        const color = index <= progressIndex ? '#1f93ff' : '#cbd5e0';

        ctx.fillStyle = color;
        ctx.fillRect(x, y, barWidth, barHeight);
      });
    },

    handleAudioLoaded() {
      const audio = this.$refs.audioElement;
      this.duration = audio.duration;
      this.seekPosition = 0;

      // Set initial volume
      audio.volume = this.volume;
    },

    handleTimeUpdate() {
      const audio = this.$refs.audioElement;
      this.currentTime = audio.currentTime;
      this.seekPosition = audio.currentTime;

      // Redraw waveform to update progress
      this.drawWaveform();
    },

    handleAudioEnded() {
      this.isPlaying = false;
      this.currentTime = 0;
      this.seekPosition = 0;
    },

    handleAudioError() {
      this.hasError = true;
    },

    togglePlayPause() {
      const audio = this.$refs.audioElement;

      if (this.isPlaying) {
        audio.pause();
      } else {
        audio.play();
      }

      this.isPlaying = !this.isPlaying;
    },

    handleSeek(event) {
      const audio = this.$refs.audioElement;
      audio.currentTime = parseFloat(event.target.value);
    },

    handleWaveformClick(event) {
      const canvas = this.$refs.waveformCanvas;
      const rect = canvas.getBoundingClientRect();
      const clickX = event.clientX - rect.left;
      const percentage = clickX / rect.width;

      const audio = this.$refs.audioElement;
      audio.currentTime = percentage * this.duration;
    },

    updateVolume() {
      const audio = this.$refs.audioElement;
      audio.volume = this.volume;
      this.isMuted = false;
    },

    toggleMute() {
      const audio = this.$refs.audioElement;

      if (this.isMuted) {
        audio.volume = this.volume;
        this.isMuted = false;
      } else {
        audio.volume = 0;
        this.isMuted = true;
      }
    },

    cyclePlaybackSpeed() {
      const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
      const currentIndex = speeds.indexOf(this.playbackSpeed);
      const nextIndex = (currentIndex + 1) % speeds.length;

      this.playbackSpeed = speeds[nextIndex];

      const audio = this.$refs.audioElement;
      audio.playbackRate = this.playbackSpeed;
    },

    downloadRecording() {
      const link = document.createElement('a');
      link.href = this.recordingUrl;
      link.download = `call-recording-${this.callId}.mp3`;
      link.click();
    },

    formatTime(seconds) {
      if (!seconds || Number.isNaN(seconds)) return '0:00';

      const minutes = Math.floor(seconds / 60);
      const secs = Math.floor(seconds % 60);
      return `${minutes}:${secs.toString().padStart(2, '0')}`;
    },

    cleanup() {
      // Stop audio
      const audio = this.$refs.audioElement;
      if (audio) {
        audio.pause();
        audio.src = '';
      }

      // Close audio context
      if (this.audioContext) {
        this.audioContext.close();
      }
    },
  },
};
</script>

<template>
  <div class="call-recording-player">
    <div v-if="isLoading" class="player-loading">
      <Spinner size="small" />
      <span>{{ $t('WHATSAPP_CALLS.RECORDING_PLAYER.LOADING') }}</span>
    </div>

    <div v-else-if="hasError" class="player-error">
      <fluent-icon icon="warning" size="20" />
      <span>{{ $t('WHATSAPP_CALLS.RECORDING_PLAYER.LOAD_ERROR') }}</span>
      <woot-button size="small" @click="loadRecording">
        {{ $t('WHATSAPP_CALLS.RECORDING_PLAYER.RETRY') }}
      </woot-button>
    </div>

    <div v-else class="player-container">
      <!-- Waveform Display -->
      <div class="waveform-container" @click="handleWaveformClick">
        <canvas ref="waveformCanvas" class="waveform-canvas" />

        <!-- Progress Indicator -->
        <div
          class="progress-indicator"
          :style="{ left: `${progressPercentage}%` }"
        />

        <!-- Time Markers -->
        <div class="time-markers">
          <span v-for="marker in timeMarkers" :key="marker.time" class="marker">
            {{ formatTime(marker.time) }}
          </span>
        </div>
      </div>

      <!-- Controls -->
      <div class="player-controls">
        <div class="primary-controls">
          <!-- Play/Pause Button -->
          <woot-button
            variant="smooth"
            color-scheme="primary"
            :icon="isPlaying ? 'pause' : 'play'"
            @click="togglePlayPause"
          />

          <!-- Current Time / Total Duration -->
          <div class="time-display">
            <span class="current-time">{{ formatTime(currentTime) }}</span>
            <span class="separator">/</span>
            <span class="total-duration">{{ formatTime(duration) }}</span>
          </div>

          <!-- Playback Speed -->
          <div class="playback-speed">
            <woot-button
              variant="smooth"
              size="small"
              @click="cyclePlaybackSpeed"
            >
              {{ playbackSpeed }}x
            </woot-button>
          </div>

          <!-- Volume Control -->
          <div class="volume-control">
            <woot-button
              variant="smooth"
              :icon="volumeIcon"
              @click="toggleMute"
            />
            <input
              v-model="volume"
              type="range"
              min="0"
              max="1"
              step="0.01"
              class="volume-slider"
              @input="updateVolume"
            />
          </div>

          <!-- Download Button -->
          <woot-button
            variant="smooth"
            icon="arrow-download"
            @click="downloadRecording"
          >
            {{ $t('WHATSAPP_CALLS.RECORDING_PLAYER.DOWNLOAD') }}
          </woot-button>
        </div>

        <!-- Progress Bar -->
        <div class="progress-bar-container">
          <input
            v-model="seekPosition"
            type="range"
            min="0"
            :max="duration"
            step="0.1"
            class="progress-bar"
            @input="handleSeek"
          />
        </div>
      </div>
    </div>

    <!-- Audio Element (hidden) -->
    <audio
      ref="audioElement"
      :src="recordingUrl"
      @loadedmetadata="handleAudioLoaded"
      @timeupdate="handleTimeUpdate"
      @ended="handleAudioEnded"
      @error="handleAudioError"
    />
  </div>
</template>

<style lang="scss" scoped>
.call-recording-player {
  width: 100%;
  padding: var(--space-normal);
  background: var(--white);
  border-radius: var(--border-radius-normal);
  border: 1px solid var(--s-100);
}

.player-loading,
.player-error {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-small);
  padding: var(--space-large);
  color: var(--s-600);
}

.player-error {
  flex-direction: column;
}

.player-container {
  display: flex;
  flex-direction: column;
  gap: var(--space-normal);
}

.waveform-container {
  position: relative;
  height: 120px;
  background: var(--s-25);
  border-radius: var(--border-radius-normal);
  cursor: pointer;
  overflow: hidden;

  &:hover {
    background: var(--s-50);
  }
}

.waveform-canvas {
  width: 100%;
  height: 100%;
}

.progress-indicator {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 2px;
  background: var(--r-500);
  pointer-events: none;
  transition: left 0.1s linear;
}

.time-markers {
  position: absolute;
  bottom: 4px;
  left: 0;
  right: 0;
  display: flex;
  justify-content: space-between;
  padding: 0 var(--space-small);
  font-size: var(--font-size-mini);
  color: var(--s-500);
  pointer-events: none;
}

.player-controls {
  display: flex;
  flex-direction: column;
  gap: var(--space-small);
}

.primary-controls {
  display: flex;
  align-items: center;
  gap: var(--space-small);
  flex-wrap: wrap;
}

.time-display {
  display: flex;
  align-items: center;
  gap: var(--space-micro);
  font-size: var(--font-size-small);
  font-variant-numeric: tabular-nums;
  color: var(--s-700);

  .separator {
    color: var(--s-400);
  }
}

.playback-speed {
  margin-left: auto;
}

.volume-control {
  display: flex;
  align-items: center;
  gap: var(--space-small);

  .volume-slider {
    width: 80px;
  }
}

.progress-bar-container {
  width: 100%;
}

.progress-bar {
  width: 100%;
  height: 4px;
  background: var(--s-100);
  border-radius: 2px;
  cursor: pointer;
  appearance: none;

  &::-webkit-slider-thumb {
    appearance: none;
    width: 12px;
    height: 12px;
    background: var(--w-500);
    border-radius: 50%;
    cursor: pointer;

    &:hover {
      background: var(--w-600);
    }
  }

  &::-moz-range-thumb {
    width: 12px;
    height: 12px;
    background: var(--w-500);
    border-radius: 50%;
    border: none;
    cursor: pointer;

    &:hover {
      background: var(--w-600);
    }
  }
}

input[type='range'] {
  &::-webkit-slider-runnable-track {
    height: 4px;
    background: var(--s-100);
    border-radius: 2px;
  }

  &::-moz-range-track {
    height: 4px;
    background: var(--s-100);
    border-radius: 2px;
  }
}
</style>
