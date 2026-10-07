# Interactive Automation Rules

`send_interactive_message` uses the existing `input_select` message and WhatsApp provider. Its `action_params` must be an array containing one JSON string:

```json
{"content":"Choose a service","items":[{"title":"Prices","value":"prices"},{"title":"Order","value":"order"}]}
```

One to three options send reply buttons; four to ten send a list. An item description also selects a list. Optional list fields are `list_button` and `list_section`. The API rejects invalid shapes, duplicate values and WhatsApp limits with 422: message 1024 characters, button title 20, list title 24, reply value 200, description 72, list button 20, section 24. The action editor provides ordinary fields rather than a JSON editor. WhatsApp messages remain subject to the provider's conversation window.

`update_contact_attribute` takes `["existing_contact_text_attribute_key", "value"]`. An empty value removes that attribute. Definitions must already exist on the account. This supports persistent onboarding and opt-out state across conversations. It does not modify provider marketing permissions.

Incoming-message rules match before any matching rule runs its actions. This prevents a state change from consuming the same message as a subsequent input step. Other conversation-event behavior remains unchanged.

Legacy menus without configured next steps still store WhatsApp reply titles as incoming message content and use existing content conditions. Their reply values and behavior remain unchanged, including ordinary values prefixed with `cwflow:`. The exact generated ID format (`cwflow:` plus a 32-character hex token and 64-character hex digest) is reserved for new routed messages; historical legacy messages using that exact format remain recognized while their original menu exists. For routed menus, the display title is only presentation: the inbound provider reply ID selects the configured next step on the same conversation. Manual text matching is not required.

The feature is generic; Blurides messages, images, assignments and rules are account configuration, not hardcoded application behavior.

WhatsApp replies created by one rule execution are sent in action order through a single batch job. When a batch contains attachments, it retains the existing two-second Active Storage upload delay before sending any reply. Successful replies keep their provider message IDs, so retrying the batch skips replies already sent. Other channels and private notes retain their existing delivery jobs.

## Configuring reusable next steps

Create the destination automation first, with the actions that should run on selection. In **Send buttons or list**, each option can select **Next automation** from the current account's active, non-delayed rules. Its actions run directly on this conversation; its normal trigger and conditions are not evaluated for the explicit button selection. Destination rules still retain their ordinary event behavior, so configure their conditions to avoid unintended independent triggers.

An option can optionally set an existing contact text attribute before running the destination. For example, create a contact text attribute named `preferred_language`, configure the Arabic option to save `ar`, and choose a destination that sends your Arabic terms/service menu. Configure the English route separately. Message wording, option IDs, attributes, languages and destination actions are entirely account configuration. For consultation or payment, choose a destination that sends the configured booking or payment URL; the selection itself does not book or pay.

The JSON API adds an optional `next_step` to an item:

```json
{"content":"Choose a language","items":[{"title":"Arabic","value":"language_ar","next_step":{"automation_rule_id":42,"contact_attribute":{"key":"preferred_language","value":"ar"}}},{"title":"English","value":"language_en","next_step":{"automation_rule_id":43}}]}
```

The API rejects cross-account, inactive and delayed destination rules, unexpected keys and attributes that are not existing contact text definitions. It validates the destination again at click time. An empty attribute value removes the attribute. A saved route with a deleted or unavailable target is shown as unavailable in the editor. Create equivalent destinations and attributes in each client account rather than reusing IDs from another account.

The editor includes a live message/route preview. When any option has a route, this becomes a routed menu: an option with no next step ends that menu and does not run title-matching rules. If every option has no next step, the entire message remains a legacy menu.

## Step identity and safe failure

Routed menus replace configured values with provider IDs containing a unique menu token and a digest of each stable configured option value. Translated or repeated titles do not affect selection identity. The original values and route snapshot are retained with the outgoing message, and the conversation records its current menu and selected value. A newer interactive menu replaces the old one. Replies to previous menus, changed/deactivated source or destination rules, wrong outbound reply context, or already-consumed steps are ignored and never fall through to text-matching rules. Explicit chains are limited to 20 menus; a fresh normally-triggered menu starts a new chain. There is no automatic recursive rule execution.

Selection is claimed durably before any destination side effects. Repeated provider callbacks, repeated listener dispatch and second clicks cannot run that menu's actions twice. This is at-most-once execution: if a destination action fails after the claim, clicking again does not retry arbitrary side effects. Review the conversation and send a new menu to restart when needed. Existing WhatsApp batch delivery retains its own retry/unsent-message behavior. No delivery success is inferred from claiming a step. The current conversation step records `claimed`, `completed`, `failed`, `unavailable`, or `step_limit` for inspection; `completed` means actions ran, not that the provider delivered the messages. Retrying a failed interactive message preserves its option IDs and routes while clearing its failed-send metadata.

No migration, production account data change, deployment, payment processing, booking API call, or plan/license change is part of this feature.

## Verification

Run the Rails regression specs with the repository's configured Ruby 3.4.4, installed bundle, PostgreSQL test database and normal test services:

```sh
bundle exec rspec spec/services/automation_rules/interactive_action_validation_service_spec.rb spec/services/automation_rules/interactive_flow_service_spec.rb spec/services/automation_rules/interactive_reply_service_spec.rb spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb
pnpm test app/javascript/dashboard/components/widgets/AutomationInteractiveMessageInput.spec.js
```

For a dependency-free, isolated check of the actual validation/flow/reply services:

```sh
ruby script/verify_interactive_automation_services.rb
```

The isolated harness uses in-memory doubles for Active Record, locks, account records and target effects. Its assertions do not substitute for Rails, SQL/concurrency, webhook parsing, provider delivery, or visual browser verification.
