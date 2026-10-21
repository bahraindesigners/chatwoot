<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import EvolutionAPI from 'dashboard/api/channel/evolutionChannel';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inboxId: { type: [Number, String], required: true },
  autoPair: { type: Boolean, default: false },
});
const { t } = useI18n();
const state = ref('loading');
const qr = ref('');
const busy = ref(false);
const error = ref('');
const reauthorizationRequired = ref(false);
const POLL_INTERVAL_MS = 5000;
const { run, abort } = useAbortableRequest();
let timer;
let active = true;
let refreshVersion = 0;
const connected = computed(() => state.value === 'open');
const statusLabel = computed(() => {
  if (connected.value) return t('INBOX_MGMT.EVOLUTION.CONNECTED');
  if (state.value === 'loading') return t('INBOX_MGMT.EVOLUTION.CHECKING');
  return t('INBOX_MGMT.EVOLUTION.NOT_CONNECTED');
});

async function refresh() {
  clearTimeout(timer);
  if (!active || busy.value) return;
  refreshVersion += 1;
  const version = refreshVersion;
  try {
    const response = await run(signal =>
      EvolutionAPI.status(props.inboxId, { signal })
    );
    if (!active || !response || version !== refreshVersion) return;
    state.value = response.data.state;
    qr.value = response.data.qr || '';
    reauthorizationRequired.value = response.data.reauthorization_required;
    error.value = '';
  } catch (failure) {
    if (!active) return;
    error.value =
      failure.response?.data?.message || t('INBOX_MGMT.EVOLUTION.ERROR');
  } finally {
    if (active && !busy.value && version === refreshVersion) {
      timer = setTimeout(refresh, POLL_INTERVAL_MS);
    }
  }
}

async function pair() {
  if (busy.value) return;
  busy.value = true;
  refreshVersion += 1;
  error.value = '';
  qr.value = '';
  clearTimeout(timer);
  abort();
  try {
    const response = await run(signal =>
      EvolutionAPI.qr(props.inboxId, { signal })
    );
    if (!active || !response) return;
    state.value = response.data.state;
    qr.value = response.data.qr || '';
    reauthorizationRequired.value = false;
  } catch (failure) {
    if (!active) return;
    error.value =
      failure.response?.data?.message || t('INBOX_MGMT.EVOLUTION.ERROR');
  } finally {
    busy.value = false;
    if (active) refresh();
  }
}

onMounted(async () => {
  await refresh();
  if (active && props.autoPair && !connected.value && !error.value) pair();
});
onUnmounted(() => {
  active = false;
  clearTimeout(timer);
  abort();
});
</script>

<template>
  <section class="flex flex-col gap-4 p-6 text-start max-w-xl mx-auto">
    <h3 class="text-lg font-medium text-n-slate-12">
      {{ t('INBOX_MGMT.EVOLUTION.PAIR_TITLE') }}
    </h3>
    <p role="status" class="text-sm text-n-slate-11">{{ statusLabel }}</p>
    <p v-if="!connected" class="text-sm text-n-slate-11">
      {{ t('INBOX_MGMT.EVOLUTION.SCAN_HINT') }}
    </p>
    <img
      v-if="qr && !connected"
      :src="qr"
      :alt="t('INBOX_MGMT.EVOLUTION.QR_ALT')"
      class="w-64 h-64 max-w-full self-center rounded-lg"
    />
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
    <p
      v-if="reauthorizationRequired"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('INBOX_MGMT.EVOLUTION.REAUTHORIZE_REQUIRED') }}
    </p>
    <p v-if="connected" class="text-sm text-n-slate-11">
      {{ t('INBOX_MGMT.EVOLUTION.TEST_HINT') }}
    </p>
    <router-link
      v-if="connected && !reauthorizationRequired && autoPair"
      :to="{ name: 'inbox_dashboard', params: { inboxId } }"
      class="self-start"
    >
      <Button :label="t('INBOX_MGMT.FINISH.BUTTON_TEXT')" />
    </router-link>
    <Button
      class="self-start"
      :label="
        connected
          ? t('INBOX_MGMT.EVOLUTION.REAUTHORIZE')
          : t('INBOX_MGMT.EVOLUTION.SHOW_QR')
      "
      :is-loading="busy"
      :disabled="busy"
      @click="pair"
    />
  </section>
</template>
