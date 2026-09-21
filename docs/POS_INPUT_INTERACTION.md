# POS input and runtime interaction

The POS keeps its existing Hive/authentication/business services. This pass changes
input presentation, locale propagation and confirmation behavior only.

## Input ownership

`PosOnScreenTextField` owns no second text buffer. Its caller's controller is the
source of truth. Touch and physical edits run the same formatters and notify
`onChanged` immediately. Selection changes alone do not call it. A controller swap
or widget disposal removes listeners. The dock reports its measured height to the
POS viewport and scrolls the focused field above it after resizing.

`PosInputMode` separates TEXT, NUMBER, DECIMAL and PIN. `PosKeyboard` owns the text
layout; `PinPad` owns numeric/PIN keys. The old `OnScreenKeyboard` and `pin_button`
entry points are compatibility exports/adapters, not additional layouts. Text
backspace removes a whole grapheme. Numeric input preserves selection, decimal
precision and leading PIN zeroes. No input values are logged.

Form-backed docks never display a second input box. A standalone prompt, such as
naming a takeaway without an existing form, explicitly requests its one visible
input. Numeric standalone prompts likewise display their own value.

## Audited paths

| Path | Input behavior |
| --- | --- |
| Login and Lock | Shared PIN pad always visible; masked live digits; Login uses Sign in/Enter, Lock automatically unlocks on a matching PIN |
| Staff create/change and admin verification | Same authentication pad; masked draft; Save/Confirm or Enter, retaining existing validation |
| Reservations | Shared controller fields for name, phone, guests and notes; time selector uses shared numeric pad |
| Menu editing/search and prices | Shared fields with live callbacks; existing slug/price formatters retained |
| Packages | Shared text/number/decimal fields; removed temporary keyboard buffers |
| Inventory | POS inventory remains read-only; its search field uses shared live input |
| Settings | Shared admin field adapter; optional keyboard preference persists per terminal |
| Printer settings | Shared numeric pad for IP entry; existing fixed configuration/validation unchanged |
| Order quantities, payments, comments and time | Existing adapters use the same text/numeric components; transaction rules unchanged |

Developer/support credentials and native date/time pickers keep their dedicated
platform controls. They are not alternate POS keyboard layouts. Manager does not
activate the POS keyboard preference or locale scope.

The optional on-screen keyboard preference affects operational text/number input.
Authentication PIN pads explicitly opt out of that preference. Staff PIN forms
also retain their touch pad. Input remains disabled while the owning flow validates.

## Localization

`PosLocaleHost` listens to Hive's persisted `defaultLanguage` above the Navigator.
It does not replace routes or discard drafts. SDK Material localization delegates
and `PosText`/the POS string catalog consume that locale. Settings writes language
when selected; Menu's language action uses the same setter. Keyboard alphabet
selection can be local to typing; explicitly Georgian/English catalog fields keep
their requested alphabet. User-authored names/notes and PIN values are not catalog
entries. Further UI copy must be added to the shared catalog, not cached in a
screen-local language flag.

## Layout and shutdown

Login and Lock share a right-aligned business date/clock. Home uses a neutral
work-date badge beside the clock, including compact widths.
Quit is a rounded Vynic dialog with cancellation and a destructive primary action.
It calls the existing `PosQuit.prepare` coordinator without changing readiness,
Hive flushing, service shutdown, Edge ownership or update recovery.

## Validation

`pos_interaction_pass_test.dart` exercises 800×600, 1024×768 and 1440×900 layouts,
actual Reservations/Menu/Inventory fields, live text/decimal/PIN input, Login/Lock/
Staff PIN visibility when optional input is off, explicit authentication, locale
switching with open dialogs and preserved drafts. Login also has narrow/150% scale
coverage. Existing safe-quit, updater-readiness, admin rendering and Home refresh
suites cover compatibility. Set `VYNIC_DUMP_DIR` for review images.

This is source validation on macOS; it does not publish or install a Windows release.
