import { shallowMount } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import AutomationInteractiveMessageInput from './AutomationInteractiveMessageInput.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

let store;
let payload;

beforeEach(() => {
  store = {
    dispatch: vi.fn(),
    getters: reactive({
      getCurrentAccountId: '1',
      'automations/getAutomations': [
        { id: 10, account_id: 1, name: 'English flow', active: true },
        { id: 11, account_id: 1, name: 'Spanish flow', active: true },
        { id: 12, account_id: 1, name: 'Inactive', active: false },
        { id: 13, account_id: 2, name: 'Other account', active: true },
        {
          id: 14,
          account_id: 1,
          name: 'Delayed',
          active: true,
          execution_delay: 60,
        },
      ],
      'attributes/getAttributes': [
        {
          id: 1,
          attribute_key: 'language',
          attribute_display_name: 'Language',
          attribute_model: 'contact_attribute',
          attribute_display_type: 'text',
        },
        {
          id: 2,
          attribute_key: 'status',
          attribute_model: 'conversation_attribute',
          attribute_display_type: 'text',
        },
        {
          id: 3,
          attribute_key: 'score',
          attribute_model: 'contact_attribute',
          attribute_display_type: 'number',
        },
      ],
    }),
  };
  payload = {
    content: 'Choose a language',
    items: [{ title: 'English', value: 'language_en' }],
  };
});

const mountInput = () =>
  shallowMount(AutomationInteractiveMessageInput, {
    props: { modelValue: JSON.stringify(payload) },
    global: {
      plugins: [
        {
          install: app => {
            app.config.globalProperties.$store = store;
          },
        },
      ],
    },
  });
const latestPayload = wrapper =>
  JSON.parse(wrapper.emitted('update:modelValue').at(-1)[0]);

describe('AutomationInteractiveMessageInput option routes', () => {
  it('loads account-scoped choices and excludes inactive, delayed and foreign rules', () => {
    const wrapper = mountInput();
    expect(store.dispatch).toHaveBeenCalledWith('automations/get');
    expect(store.dispatch).toHaveBeenCalledWith('attributes/get');
    expect(
      wrapper.findAll('[data-testid="next-step"] option').map(o => o.attributes('value'))
    ).toEqual(['', '10', '11']);
  });

  it('adds a next step without changing the configured reply value', async () => {
    const wrapper = mountInput();
    await wrapper.find('[data-testid="next-step"]').setValue('10');
    expect(latestPayload(wrapper)).toEqual({
      ...payload,
      items: [
        {
          ...payload.items[0],
          next_step: { automation_rule_id: 10 },
        },
      ],
    });
  });

  it('removes the complete route when no next step is selected', async () => {
    payload.items[0].next_step = {
      automation_rule_id: 10,
      contact_attribute: { key: 'language', value: 'en' },
    };
    const wrapper = mountInput();
    await wrapper.find('[data-testid="next-step"]').setValue('');
    expect(latestPayload(wrapper).items[0]).toEqual({
      title: 'English',
      value: 'language_en',
    });
  });

  it('offers only contact text attributes and persists the selected value', async () => {
    payload.items[0].next_step = { automation_rule_id: 10 };
    const wrapper = mountInput();
    expect(
      wrapper.findAll('[data-testid="contact-attribute"] option').map(o => o.attributes('value'))
    ).toEqual(['', 'language']);
    await wrapper.find('[data-testid="contact-attribute"]').setValue('language');
    await wrapper.setProps({ modelValue: JSON.stringify(latestPayload(wrapper)) });
    wrapper.findAllComponents(NextInput).at(-1).vm.$emit('update:modelValue', 'en');
    expect(latestPayload(wrapper).items[0].next_step).toEqual({
      automation_rule_id: 10,
      contact_attribute: { key: 'language', value: 'en' },
    });
  });

  it('preserves contact settings when changing the next step and removes optional attributes', async () => {
    payload.items[0].next_step = {
      automation_rule_id: 10,
      contact_attribute: { key: 'language', value: 'en' },
    };
    const wrapper = mountInput();
    await wrapper.find('[data-testid="next-step"]').setValue('11');
    expect(latestPayload(wrapper).items[0].next_step).toEqual({
      automation_rule_id: 11,
      contact_attribute: { key: 'language', value: 'en' },
    });
    await wrapper.setProps({ modelValue: JSON.stringify(latestPayload(wrapper)) });
    await wrapper.find('[data-testid="contact-attribute"]').setValue('');
    expect(latestPayload(wrapper).items[0].next_step).toEqual({
      automation_rule_id: 11,
    });
  });

  it('preserves routes, descriptions and stable values during ordinary message edits', async () => {
    payload.items[0].description = 'Continue in English';
    payload.items[0].next_step = {
      automation_rule_id: 10,
      contact_attribute: { key: 'language', value: 'en' },
    };
    payload.list_button = 'Languages';
    payload.list_section = 'Choose';
    const wrapper = mountInput();
    await wrapper.find('textarea').setValue('Updated prompt');
    expect(latestPayload(wrapper)).toEqual({ ...payload, content: 'Updated prompt' });
    await wrapper.setProps({ modelValue: JSON.stringify(latestPayload(wrapper)) });
    wrapper.findAllComponents(NextInput)[0].vm.$emit('update:modelValue', 'English renamed');
    expect(latestPayload(wrapper).items[0]).toEqual({
      ...payload.items[0],
      title: 'English renamed',
    });
  });

  it('removes an option without disturbing the remaining route and stable value', () => {
    payload.items = [
      { title: 'Spanish', value: 'language_es' },
      {
        title: 'English',
        value: 'language_en',
        next_step: { automation_rule_id: 10 },
      },
    ];
    const wrapper = mountInput();
    const removeButton = wrapper.findAllComponents(NextButton).find(
      button => button.attributes('label') === 'AUTOMATION.INTERACTIVE.REMOVE_OPTION'
    );
    removeButton.vm.$emit('click');
    expect(latestPayload(wrapper).items).toEqual([payload.items[1]]);
  });

  it('warns about invalid saved routes and attributes without silently deleting them', () => {
    payload.items[0].next_step = {
      automation_rule_id: 13,
      contact_attribute: { key: 'removed_attribute', value: 'en' },
    };
    const wrapper = mountInput();
    expect(wrapper.findAll('[role="alert"]')).toHaveLength(2);
    expect(wrapper.text()).toContain('AUTOMATION.INTERACTIVE.INVALID_NEXT_STEP');
    expect(wrapper.text()).toContain('AUTOMATION.INTERACTIVE.INVALID_CONTACT_ATTRIBUTE');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('previews the chosen route and preserves existing JSON with no route by default', async () => {
    const wrapper = mountInput();
    expect(wrapper.find('section').text()).toContain('AUTOMATION.INTERACTIVE.NO_NEXT_STEP');
    await wrapper.find('textarea').setValue('New prompt');
    expect(latestPayload(wrapper).items).toEqual(payload.items);
    payload.items[0].next_step = {
      automation_rule_id: 10,
      contact_attribute: { key: 'language', value: 'en' },
    };
    await wrapper.setProps({ modelValue: JSON.stringify(payload) });
    expect(wrapper.find('section').text()).toContain('English flow');
    expect(wrapper.find('section').text()).toContain('language: en');
    const addButton = wrapper.findAllComponents(NextButton).find(
      button => button.attributes('label') === 'AUTOMATION.INTERACTIVE.ADD_OPTION'
    );
    addButton.vm.$emit('click');
    expect(latestPayload(wrapper).items).toEqual([
      payload.items[0],
      { title: '', value: '' },
    ]);
  });
});
