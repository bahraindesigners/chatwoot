<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import EvolutionAPI from 'dashboard/api/channel/evolutionChannel';
import types from 'dashboard/store/mutation-types';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PageHeader from '../../SettingsSubPageHeader.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const name = ref('');
const busy = ref(false);
const error = ref('');

async function create() {
  if (!name.value.trim() || busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await EvolutionAPI.create({ name: name.value.trim() });
    store.commit(`inboxes/${types.ADD_INBOXES}`, data);
    await router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: data.id },
    });
  } catch (failure) {
    error.value =
      failure.response?.data?.message || t('INBOX_MGMT.EVOLUTION.ERROR');
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="p-6 w-full">
    <PageHeader
      :header-title="t('INBOX_MGMT.EVOLUTION.TITLE')"
      :header-content="t('INBOX_MGMT.EVOLUTION.DESCRIPTION')"
    />
    <form class="flex flex-col gap-5 max-w-lg" @submit.prevent="create">
      <Input
        v-model="name"
        :label="t('INBOX_MGMT.EVOLUTION.NAME')"
        :placeholder="t('INBOX_MGMT.EVOLUTION.PLACEHOLDER')"
        :disabled="busy"
        autofocus
      />
      <p class="text-sm text-n-slate-11">
        {{ t('INBOX_MGMT.EVOLUTION.SETUP_HINT') }}
      </p>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <Button
        type="submit"
        class="self-start"
        :label="t('INBOX_MGMT.EVOLUTION.CREATE')"
        :is-loading="busy"
        :disabled="busy || !name.trim()"
      />
    </form>
  </div>
</template>
