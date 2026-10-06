<script setup>
import { computed } from 'vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
const model = defineModel({ type: Array, default: () => [] });
const attributeKey = computed({
  get: () => model.value[0] || '',
  set: value => {
    model.value = [value, model.value[1] || ''];
  },
});
const attributeValue = computed({
  get: () => model.value[1] || '',
  set: value => {
    model.value = [model.value[0] || '', value];
  },
});
</script>

<template>
  <div class="grid gap-3 sm:grid-cols-2">
    <NextInput
      v-model="attributeKey"
      :label="$t('AUTOMATION.INTERACTIVE.ATTRIBUTE_KEY')"
      :message="$t('AUTOMATION.INTERACTIVE.ATTRIBUTE_HELP')"
    />
    <NextInput
      v-model="attributeValue"
      :label="$t('AUTOMATION.INTERACTIVE.ATTRIBUTE_VALUE')"
    />
  </div>
</template>
