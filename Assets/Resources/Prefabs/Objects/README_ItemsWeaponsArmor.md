# Items, Weapons, and Armor JSON

Definitions are split into three files so items (consumables, materials, etc.) stay separate from equipment that uses character sprites.

## Files

| File | Purpose |
|------|--------|
| **items.json** | General items: consumables, materials, befriending, etc. Uses `"items"` array. |
| **weapons.json** | Weapons (swords, staffs, bows, etc.). Uses `"weapons"` array. |
| **armor.json** | Armor (chest, legs, etc.). Uses `"armor"` array. |

All definitions are merged by `id` at load time, so the game and UI see one combined set.

## Parts vs images

- **items.json**  
  Use **`parts`** with **`tileGrid`** when the item is drawn in the world (e.g. dropped on the map, tile-based). Each part can have `layer`, `tileGrid`, `offset`, `size`, etc.

- **weapons.json / armor.json**  
  Use **`frontImage`** and **`sideImage`** (sprite labels) for character equipment. No `parts`/`tileGrid` needed for the character; sprites are loaded from the character Parts manifest (e.g. `MainHand/iron_sword_front.png`).  
  - `frontImage`: label for north/south facing (e.g. `"iron_sword_front"`).  
  - `sideImage`: label for east/west facing (e.g. `"iron_sword_side"`).  
  If omitted, the loader falls back to `{id}_front` and `{id}_side`.

## Per-facing offset and rotation (weapons.json / armor.json)

You can define **`equipmentOffsets`** on each weapon or armor so it orients correctly (e.g. sword vs staff). When the character faces left, `x` and `rotation` are mirrored automatically so the item stays in the same hand.

```json
"equipmentOffsets": {
  "front": { "x": 0.2, "y": 0.05, "rotation": -25 },
  "side":  { "x": 0.25, "y": 0.02, "rotation": -15 },
  "back":  { "x": 0.15, "y": -0.02, "rotation": -40 }
}
```

- **front** – offset (x, y) and **rotation** (degrees around Z) when facing camera (north/south).
- **side** – when facing east/west.
- **back** – when facing away. Omit any key to use built-in defaults for that facing.

Optional. If omitted, the game uses built-in defaults. Inspector overrides on Character Customizer are still available as a fallback.

## Example weapon entry (weapons.json)

```json
{
  "id": "iron_sword",
  "name": "Iron Sword",
  "description": "A well-crafted iron sword",
  "type": "weapon",
  "value": 50,
  "stackable": false,
  "inventorySize": { "width": 3, "height": 1 },
  "frontImage": "iron_sword_front",
  "sideImage": "iron_sword_side",
  "weaponData": {
    "weaponType": "sword",
    "damageDie": 8,
    "range": 1
  }
}
```

## Example armor entry (armor.json)

```json
{
  "id": "leather_armor",
  "name": "Leather Armor",
  "type": "armor",
  "value": 40,
  "frontImage": "leather_armor_front",
  "sideImage": "leather_armor_side",
  "armorData": {
    "armorType": "light",
    "armorClass": 11,
    "slot": "chest"
  }
}
```

## Example item with tile parts (items.json)

For world/tile display (e.g. dropped item on map):

```json
{
  "id": "health_potion",
  "name": "Health Potion",
  "type": "consumable",
  "parts": [
    {
      "layer": "low",
      "tileGrid": [["item_atlas-1"]],
      "offset": { "x": 0, "y": 0 },
      "size": { "width": 32, "height": 32 },
      "tileSize": 32
    }
  ]
}
```
