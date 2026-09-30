<script setup>
import { computed } from 'vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
const model = defineModel({ type: String, default: '' });
const MAX_ITEMS = 10;
const MAX_BUTTONS = 3;
const payload = computed(() =>
  model.value
    ? JSON.parse(model.value)
    : { content: '', items: [{ title: '', value: '' }] }
);
const isList = computed(
  () =>
    payload.value.items.length > MAX_BUTTONS ||
    payload.value.items.some(item => item.description)
);
const update = patch => {
  const next = { ...payload.value, ...patch };
  const list =
    next.items.length > MAX_BUTTONS ||
    next.items.some(item => item.description);
  ['list_button', 'list_section'].forEach(key => {
    if (!list || !next[key]) delete next[key];
  });
  model.value = JSON.stringify(next);
};
const updateItem = (index, key, value) =>
  update({
    items: payload.value.items.map((item, i) =>
      i === index ? { ...item, [key]: value } : item
    ),
  });
const addItem = () =>
  update({ items: [...payload.value.items, { title: '', value: '' }] });
const removeItem = index =>
  update({ items: payload.value.items.filter((_, i) => i !== index) });
</script>

<template>
  <div class="flex flex-col gap-3">
    <label class="text-sm text-n-slate-12">
      {{ $t('AUTOMATION.INTERACTIVE.MESSAGE') }}
      <textarea
        :value="payload.content"
        maxlength="1024"
        rows="3"
        class="w-full mt-1 p-3 rounded-lg bg-n-alpha-1 outline outline-1 outline-n-weak focus:outline-n-brand"
        @input="update({ content: $event.target.value })"
      />
    </label>
    <p v-if="isList" class="m-0 text-sm text-n-slate-11">
      {{ $t('AUTOMATION.INTERACTIVE.LIST_HELP') }}
    </p>
    <p v-else class="m-0 text-sm text-n-slate-11">
      {{ $t('AUTOMATION.INTERACTIVE.BUTTON_HELP') }}
    </p>
    <div
      v-for="(item, index) in payload.items"
      :key="index"
      class="flex items-end gap-2"
    >
      <div class="grid flex-1 gap-2 sm:grid-cols-2">
        <NextInput
          :model-value="item.title"
          :label="$t('AUTOMATION.INTERACTIVE.OPTION_TITLE')"
          @update:model-value="updateItem(index, 'title', $event)"
        />
        <NextInput
          :model-value="item.value"
          :label="$t('AUTOMATION.INTERACTIVE.REPLY_VALUE')"
          @update:model-value="updateItem(index, 'value', $event)"
        />
      </div>
      <NextButton
        sm
        slate
        icon="i-lucide-trash"
        :label="$t('AUTOMATION.INTERACTIVE.REMOVE_OPTION')"
        :disabled="payload.items.length === 1"
        @click="removeItem(index)"
      />
    </div>
    <NextButton
      sm
      faded
      blue
      icon="i-lucide-plus"
      :label="$t('AUTOMATION.INTERACTIVE.ADD_OPTION')"
      :disabled="payload.items.length >= MAX_ITEMS"
      @click="addItem"
    />
    <div v-if="isList" class="grid gap-3 sm:grid-cols-2">
      <NextInput
        :model-value="payload.list_button || ''"
        :label="$t('AUTOMATION.INTERACTIVE.LIST_BUTTON')"
        @update:model-value="update({ list_button: $event })"
      />
      <NextInput
        :model-value="payload.list_section || ''"
        :label="$t('AUTOMATION.INTERACTIVE.LIST_SECTION')"
        @update:model-value="update({ list_section: $event })"
      />
    </div>
  </div>
</template>
