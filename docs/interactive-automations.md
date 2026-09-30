# Interactive Automation Rules

`send_interactive_message` uses the existing `input_select` message and WhatsApp provider. Its `action_params` must be an array containing one JSON string:

```json
{"content":"Choose a service","items":[{"title":"Prices","value":"prices"},{"title":"Order","value":"order"}]}
```

One to three options send reply buttons; four to ten send a list. An item description also selects a list. Optional list fields are `list_button` and `list_section`. The API rejects invalid shapes, duplicate values and WhatsApp limits with 422: message 1024 characters, button title 20, list title 24, reply value 200, description 72, list button 20, section 24. The action editor provides ordinary fields rather than a JSON editor. WhatsApp messages remain subject to the provider's conversation window.

`update_contact_attribute` takes `["existing_contact_text_attribute_key", "value"]`. An empty value removes that attribute. Definitions must already exist on the account. This supports persistent onboarding and opt-out state across conversations. It does not modify provider marketing permissions.

Incoming-message rules match before any matching rule runs its actions. This prevents a state change from consuming the same message as a subsequent input step. Other conversation-event behavior remains unchanged.

WhatsApp reply titles are currently stored as incoming message content. Configure content conditions using the displayed title, not the opaque reply value. Country or step context must also be included where titles repeat.

The feature is generic; Blurides messages, images, assignments and rules are account configuration, not hardcoded application behavior.

WhatsApp replies created by one rule execution are sent in action order through a single batch job. When a batch contains attachments, it retains the existing two-second Active Storage upload delay before sending any reply. Successful replies keep their provider message IDs, so retrying the batch skips replies already sent. Other channels and private notes retain their existing delivery jobs.
