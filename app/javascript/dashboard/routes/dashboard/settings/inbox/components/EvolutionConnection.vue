<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import EvolutionAPI from 'dashboard/api/channel/evolutionChannel';
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
let timer;
let active = true;
const connected = computed(() => state.value === 'open');
const statusLabel = computed(() => {
  if (connected.value) return t('INBOX_MGMT.EVOLUTION.CONNECTED');
  if (state.value === 'loading') return t('INBOX_MGMT.EVOLUTION.CHECKING');
  return t('INBOX_MGMT.EVOLUTION.NOT_CONNECTED');
});

async function refresh() {
  try {
    const { data } = await EvolutionAPI.status(props.inboxId);
    if (!active) return;
    state.value = data.state;
    if (connected.value) {
      qr.value = '';
      clearTimeout(timer);
    } else if (qr.value) {
      timer = setTimeout(refresh, 5000);
    }
  } catch (failure) {
    if (!active) return;
    error.value =
      failure.response?.data?.message || t('INBOX_MGMT.EVOLUTION.ERROR');
    clearTimeout(timer);
  }
}

async function pair() {
  busy.value = true;
  error.value = '';
  qr.value = '';
  clearTimeout(timer);
  try {
    const { data } = await EvolutionAPI.qr(props.inboxId);
    if (!active) return;
    state.value = data.state;
    qr.value = data.qr || '';
    if (!connected.value && !qr.value) {
      error.value = t('INBOX_MGMT.EVOLUTION.QR_PENDING');
    }
    await refresh();
  } catch (failure) {
    if (!active) return;
    error.value =
      failure.response?.data?.message || t('INBOX_MGMT.EVOLUTION.ERROR');
  } finally {
    busy.value = false;
  }
}

onMounted(async () => {
  await refresh();
  if (active && props.autoPair && !connected.value && !error.value) pair();
});
onUnmounted(() => {
  active = false;
  clearTimeout(timer);
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
    <p v-if="connected" class="text-sm text-n-slate-11">
      {{ t('INBOX_MGMT.EVOLUTION.TEST_HINT') }}
    </p>
    <router-link
      v-if="connected && autoPair"
      :to="{ name: 'inbox_dashboard', params: { inboxId } }"
      class="self-start"
    >
      <Button :label="t('INBOX_MGMT.FINISH.BUTTON_TEXT')" />
    </router-link>
    <Button
      v-if="!connected"
      class="self-start"
      :label="t('INBOX_MGMT.EVOLUTION.SHOW_QR')"
      :is-loading="busy"
      :disabled="busy"
      @click="pair"
    />
  </section>
</template>
