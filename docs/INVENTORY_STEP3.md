# Inventory Step 3 — Menu → Stock Consumption / Technological Cards

## Core principle

One generalized definition answers one question:

```text
When one Menu Item is sold,
which Stock Items should eventually be consumed, and how much of each?
```

A bottled drink, a draft pour and a four-ingredient recipe are the same domain
concept and differ only in how many components they carry. There is deliberately
no separate "direct link", "recipe" and "draft beverage" subsystem — the Manager
UI presents the first two more simply over the same model.

Step 3 defines consumption. It moves no stock: creating, editing or disabling a
card writes no `StockMovement`, and current stock is unchanged. Automatic Sale
consumption is Step 4.

## The definition

`MenuConsumptionRecipe` is Venue-scoped and tied to stable Menu identity from
Phase 4.5/4.6 — `MenuItem.id` and `MenuItemVariant.id`, never a display name.

```text
menuItemId + variantId?   one active definition per product
yieldQuantity             how many sold units the components describe
revision                  bumped on every save
isActive                  disabled cards stay readable
```

`variantId` is nullable for the foreign key, but the uniqueness rule uses a
non-null discriminator:

```text
variantKey = variantId ?? ''
@@unique([menuItemId, variantKey])
```

PostgreSQL treats NULLs as distinct, so a unique index over a nullable
`variantId` would have allowed two definitions for the same unvaried Menu Item.
The shadow column is what makes "one definition per product" a database rule
rather than an application hope.

## Components

```text
stockItemId             durable identity
stockItemNameSnapshot   historical/editor display context
quantity / unit         as entered, for the whole yield  ("3.5 kg")
baseQuantity / baseUnit normalized to the item's base unit
baseQuantityPerUnit     baseQuantity / yieldQuantity     ("0.035000 kg")
```

`baseQuantityPerUnit` is the one number a later step consumes. Dividing once,
here, at a declared scale, is what stops "100 khinkali need 3.5 kg" and
"0.035 kg each" from ever disagreeing.

One Stock Item may be used by many Menu Items and one Menu Item may use many
Stock Items. It is many-to-many through components; nothing forces a pairing.

## Exact quantities

Quantities are `Decimal(18,3)` and per-unit consumption is `Decimal(18,6)`, both
crossing the wire as fixed-scale decimal strings. No JavaScript or Dart binary
float is durable truth here, exactly as in Step 2.

## Unit conversion

Recipe conversion is deliberately narrower than receiving conversion:

```text
1. the entered unit is the item's base unit;
2. the global mass/volume table (1 kg = 1000 g, 1 L = 1000 ml);
3. otherwise refuse.
```

```text
35 g of an item held in kg    -> 0.035 kg
500 ml of a tank held in L    -> 0.500 L
1 bottle of a bottled item    -> 1 bottle
kg -> L                       INVALID
box -> bottle                 INVALID, even when configured for receiving
```

Item packaging is excluded on purpose. `1 box = 24 bottle` is how a venue buys
lemonade, never how it serves it, and letting a purchase ratio through would
turn a data-entry slip into a 24x consumption error. `recipeUnitsFor` is the one
authority for what a card may offer: `g`/`kg` for mass, `ml`/`L` for volume, and
the base unit itself for a counted item.

## Draft beverages

A keg is procurement packaging; the litre is consumption truth.

```text
Receiving   1 box = 30 L      (item packaging, Step 2)
Recipe      Draft Beer 0.3L -> 0.300 L
            Draft Beer 0.5L -> 0.500 L
            Pitcher 1L      -> 1.000 L
```

All three reference the same Stock Item. There is no separate keg recipe system.

## Variants

Phase 4.6 gave every variant a stable id, so a size-specific card is addressed
by `menuItemId + variantId` and never by a label. A Menu Item with no meaningful
variants uses `variantId = null`.

## Yield

The default is a per-unit definition (`yieldQuantity = 1`). A batch definition
is allowed where it simplifies kitchen entry — "100 khinkali from 3.5 kg beef" —
and is normalized at save time, so consumption semantics are identical.

## Manager surface

```text
მარაგები
├── პროდუქტები   Stock Items, derived balance, packaging, usage
├── მომწოდებლები  Suppliers
├── მიღებები      Receiving
└── რეცეპტები     Menu-oriented consumption definitions
```

The Recipes list is Menu-oriented: a product with no definition is a
first-class row marked unconfigured, because the gap is what a Manager opens
the section to find. There is no "add recipe" button — a definition always
starts from a product the venue already sells.

The editor has two presentation modes over one payload: `მარაგთან
დაკავშირება` for a direct product (one component, one sold unit) and
`რეცეპტი` for an ingredient list with a yield. It shows the selling price as
read-only context and the normalized base quantity while it is still editable,
so "500 ml" is visibly "0.5 ლ" before anything is saved.

Disabling stops applying a card without deleting it: a Step 4 snapshot may
still name it, and a Manager who disabled the wrong one wants it back rather
than retyped.

## Stock Item creation assist

From the editor, `მარაგის პროდუქტის შექმნა` opens the Stock Item form
pre-filled with the Menu Item's name and nothing else. Base unit, packaging,
threshold and SKU stay real decisions. The created row gets its own UUID:
`MenuItem.id` and `StockItem.id` are never the same identity.

## Reverse usage lookup

The Stock Item detail answers "who is using this?" before a rename or a
disable:

```text
Beef
  ხინკალი   0.035 კგ
  Burger    0.15 კგ
```

## Localization

User-facing Inventory labels are Georgian; storage and the wire keep the stable
English enum codes, so no persisted value depends on language.

```text
kg -> კგ    g -> გ    L -> ლ    ml -> მლ
piece -> ცალი   bottle -> ბოთლი   pack -> შეკვრა   box -> ყუთი

Base Unit      -> საბაზო ერთეული
Minimum Stock  -> მინიმალური ნაშთი
Purchase Units -> შესყიდვის შეფუთვა   ("1 ყუთი = 24 ბოთლი")
```

Minimum stock keeps its Step 1 meaning — a warning threshold, not a balance —
and now says so in both the editor and the detail. The low-stock rule itself is
unchanged.

## POS projection

`GET /edge/inventory/catalog` becomes version 3 and adds `recipes`: the active
definitions with both identities (`menuItemId`/`posMenuItemId`,
`variantId`/`posMenuVariantId`), the recipe `revision`, and each component's
`stockItemId`, `baseQuantityPerUnit` and `baseUnit`.

The POS is a reader. It never authors a recipe and never recomputes a
consumption quantity; it holds Cloud's exact decimal text so the two clients
cannot disagree. A failed refresh leaves the last good projection intact and
never blocks restaurant operation. Nothing consumes stock yet.

## Backup and restore

Recipes ride inside the existing `inventoryCatalog` value the POS backup already
carries, so no new backup authority appears. Cloud remains the sole recipe
administration authority; the POS has no writable copy to conflict with it. A
backup written before Step 3 restores with an empty recipe list and is corrected
by the next Device pull.

## Global audit

```text
RECIPE_CREATED  RECIPE_UPDATED  RECIPE_DISABLED
entityType = RECIPE, entityId = MenuConsumptionRecipe.id
```

Details carry `menuItemId`, `menuItemName`, `variantId`, `variantLabel`,
`yieldQuantity`, `componentCount`, `isActive` and `revision` — a summary, not
the card. The components are readable at the recipe itself.

## Historical / Step 4 readiness

Editing a card today must not rewrite what a past sale consumed. The model is
shaped so Step 4 snapshots the definition it used rather than joining back:
`revision` names exactly which version applied, and `baseQuantityPerUnit` is
already the number to copy. The consumption snapshot itself is not implemented
here.

## Tenant safety

`MenuConsumptionRecipe` and `MenuConsumptionComponent` are Venue-scoped and
every write resolves `Staff -> Venue`. The Menu Item, the variant and every
Stock Item are re-proven against that Venue; a variant is checked against its
own Menu Item rather than trusted. Proven against PostgreSQL: one Venue cannot
recipe-link another's Menu Item, consume another's Stock Item, or read, list,
project or disable another's recipes.

## Costing readiness

No purchase cost is copied into a definition: a recipe describes physical
consumption, not procurement price. A later step multiplies
`baseQuantityPerUnit` by the inventory effective cost preserved in Step 2's
`ReceivingLine.effectiveBaseUnitCost`. Step 3 computes no COGS.

## Yield / pour loss

Not modelled. `baseQuantityPerUnit` is theoretical consumption — 0.5 L sold is
0.5 L consumed. Expected yield and pour/trimming loss belong on the component in
a later step and need no change to anything here.

## Deployment order

1. Backend migration `20260910120000_inventory_step3_menu_consumption` and the
   backend application.
2. Manager clients with the Recipes UI.
3. POS clients with the extended projection.

The migration is additive. An older Manager ignores the new endpoints; an older
POS ignores the new catalog field. A newer POS against an older backend receives
a v2 catalog and reads an empty recipe list.
