<script setup>
import { computed, onMounted } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import NextInput from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
const model = defineModel({ type: String, default: '' });
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const automations = useMapGetter('automations/getAutomations');
const attributes = useMapGetter('attributes/getAttributes');
const nextSteps = computed(() =>
  automations.value.filter(
    rule =>
      rule.active &&
      !rule.execution_delay &&
      rule.account_id === Number(accountId.value)
  )
);
const contactAttributes = computed(() =>
  attributes.value.filter(
    attribute =>
      attribute.attribute_model === 'contact_attribute' &&
      attribute.attribute_display_type === 'text'
  )
);
onMounted(() => {
  store.dispatch('automations/get');
  store.dispatch('attributes/get');
});
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
const updateNextStep = (index, ruleId) => {
  const items = payload.value.items.map((item, i) => {
    if (i !== index) return item;
    const next = { ...item };
    if (ruleId) {
      next.next_step = {
        ...item.next_step,
        automation_rule_id: Number(ruleId),
      };
    } else {
      delete next.next_step;
    }
    return next;
  });
  update({ items });
};
const updateContactAttribute = (index, key, value) => {
  const nextStep = { ...payload.value.items[index].next_step };
  if (key) {
    nextStep.contact_attribute = { key, value };
  } else {
    delete nextStep.contact_attribute;
  }
  updateItem(index, 'next_step', nextStep);
};
const routeName = item =>
  nextSteps.value.find(rule => rule.id === item.next_step?.automation_rule_id)
    ?.name;
const invalidAttribute = item =>
  item.next_step?.contact_attribute &&
  !contactAttributes.value.some(
    attribute => attribute.attribute_key === item.next_step.contact_attribute.key
  );
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
      class="flex items-start gap-2 rounded-lg border border-n-weak p-3"
    >
      <div class="grid flex-1 gap-3 sm:grid-cols-2">
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
        <label class="flex flex-col gap-1 text-sm text-n-slate-12 sm:col-span-2">
          {{ $t('AUTOMATION.INTERACTIVE.NEXT_STEP') }}
          <select
            :value="item.next_step?.automation_rule_id || ''"
            class="rounded-lg bg-n-alpha-1 p-2 outline outline-1 outline-n-weak"
            data-testid="next-step"
            @change="updateNextStep(index, $event.target.value)"
          >
            <option value="">{{ $t('AUTOMATION.INTERACTIVE.NO_NEXT_STEP') }}</option>
            <option
              v-if="item.next_step && !routeName(item)"
              :value="item.next_step.automation_rule_id"
              disabled
            >
              {{ $t('AUTOMATION.INTERACTIVE.UNAVAILABLE_NEXT_STEP') }}
            </option>
            <option v-for="rule in nextSteps" :key="rule.id" :value="rule.id">
              {{ rule.name }}
            </option>
          </select>
        </label>
        <template v-if="item.next_step">
          <p class="m-0 text-sm text-n-slate-11 sm:col-span-2">
            {{ $t('AUTOMATION.INTERACTIVE.NEXT_STEP_HELP') }}
          </p>
          <p v-if="!routeName(item)" class="m-0 text-sm text-n-ruby-11 sm:col-span-2" role="alert">
            {{ $t('AUTOMATION.INTERACTIVE.INVALID_NEXT_STEP') }}
          </p>
          <label class="flex flex-col gap-1 text-sm text-n-slate-12">
            {{ $t('AUTOMATION.INTERACTIVE.SAVE_CONTACT_ATTRIBUTE') }}
            <select
              :value="item.next_step.contact_attribute?.key || ''"
              class="rounded-lg bg-n-alpha-1 p-2 outline outline-1 outline-n-weak"
              data-testid="contact-attribute"
              @change="updateContactAttribute(index, $event.target.value, item.next_step.contact_attribute?.value || '')"
            >
              <option value="">{{ $t('AUTOMATION.INTERACTIVE.NO_CONTACT_ATTRIBUTE') }}</option>
              <option
                v-if="invalidAttribute(item)"
                :value="item.next_step.contact_attribute.key"
                disabled
              >
                {{ item.next_step.contact_attribute.key }}
              </option>
              <option
                v-for="attribute in contactAttributes"
                :key="attribute.id"
                :value="attribute.attribute_key"
              >
                {{ attribute.attribute_display_name }}
              </option>
            </select>
          </label>
          <NextInput
            v-if="item.next_step.contact_attribute"
            :model-value="item.next_step.contact_attribute.value"
            :label="$t('AUTOMATION.INTERACTIVE.ATTRIBUTE_VALUE')"
            :message="$t('AUTOMATION.INTERACTIVE.ROUTE_ATTRIBUTE_HELP')"
            @update:model-value="updateContactAttribute(index, item.next_step.contact_attribute.key, $event)"
          />
          <p v-if="invalidAttribute(item)" class="m-0 text-sm text-n-ruby-11 sm:col-span-2" role="alert">
            {{ $t('AUTOMATION.INTERACTIVE.INVALID_CONTACT_ATTRIBUTE') }}
          </p>
        </template>
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
    <section class="rounded-lg border border-n-weak bg-n-alpha-1 p-3" :aria-label="$t('AUTOMATION.INTERACTIVE.PREVIEW')">
      <p class="m-0 mb-2 text-sm font-medium text-n-slate-12">{{ $t('AUTOMATION.INTERACTIVE.PREVIEW') }}</p>
      <p class="m-0 whitespace-pre-wrap text-sm text-n-slate-12">{{ payload.content }}</p>
      <ul class="m-0 mt-2 flex list-none flex-col gap-2 p-0">
        <li v-for="(item, index) in payload.items" :key="index" class="rounded-lg border border-n-weak p-2 text-sm text-n-slate-12">
          <span class="font-medium">{{ item.title || $t('AUTOMATION.INTERACTIVE.OPTION_TITLE') }}</span>
          <p v-if="item.description" class="m-0 text-n-slate-11">{{ item.description }}</p>
          <p class="m-0 text-xs text-n-slate-11">
            {{ $t('AUTOMATION.INTERACTIVE.NEXT_STEP') }}:
            {{ item.next_step ? routeName(item) || $t('AUTOMATION.INTERACTIVE.UNAVAILABLE_NEXT_STEP') : $t('AUTOMATION.INTERACTIVE.NO_NEXT_STEP') }}
          </p>
          <p v-if="item.next_step?.contact_attribute" class="m-0 text-xs text-n-slate-11">
            {{ item.next_step.contact_attribute.key }}: {{ item.next_step.contact_attribute.value || $t('AUTOMATION.INTERACTIVE.REMOVE_ATTRIBUTE') }}
          </p>
        </li>
      </ul>
    </section>
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
