# Weapon and Armor Art Guide

This guide covers how to create and hook up weapon and armor sprites so they attach correctly to the character in-game (e.g. **iron sword** in Main Hand).

Weapon and armor **definitions** live in **weapons.json** and **armor.json** (see `Assets/Resources/Prefabs/Objects/README_ItemsWeaponsArmor.md`). Each entry can set **frontImage** and **sideImage** (sprite labels); if omitted, the game uses `{id}_front` and `{id}_side`.

---

## 1. What images do you need?

### Iron sword (main-hand weapon)

- **One image per “view” you want.** The game uses the same facing as the character (Front / Back / Side). If you want the sword to look different when the character faces different ways, you need multiple sprites; otherwise one sprite is reused (and may be flipped for left-facing).
- **Suggested minimum:** one sprite for **front** and one for **side** (e.g. `iron_sword_front.png`, `iron_sword_side.png`). Back can reuse front or use its own.
- **Label = item id.** The **Sprite Library label** that the game uses when equipping is the item’s **id** from `items.json` (e.g. `iron_sword`). So you either:
  - Use **one label** and one image: e.g. one sprite with label `iron_sword` (used for all facings), or
  - Use **multiple labels** (e.g. `iron_sword_front`, `iron_sword_side`) only if you later add code to pick the label by facing; for now, a single label and one image is simplest.

**For a first pass:** create **one image** for the iron sword, e.g. `iron_sword.png`, and use the label `iron_sword` (same as the item id in `items.json`).

### Armor (e.g. chest)

- Same idea: the **label** used on the rig is the item **id** (e.g. `leather_armor`, `steel_armor`).
- You can have one image per slot (e.g. chest) and reuse one label per armor item. For multiple facings (front/back/side), you can add multiple sprites under the same category with labels like `leather_armor_front`, `leather_armor_side` and extend the game later to pick by facing; for now one sprite per armor item is enough.

---

## 2. Canvas size and sword size

- **Canvas:** Use a **fixed canvas** so pivots are consistent. Recommended:
  - **256×256** or **128×256** for a sword (portrait works well for a vertical blade).
- **Sword size on canvas:** The character body in this project is on the order of ~256–512 px tall. A sword held in hand usually looks good at about **100–200 px** blade length (depending on style). Draw the sword so that:
  - The **grip / hand attachment** is at the **bottom center** of the canvas (or wherever you will set the pivot).
  - The blade extends **up** from there (or to the side for a side view).
- **Pivot:** Set the sprite pivot to **Bottom Center** `(0.5, 0)` in Unity (Texture Import → Sprite Editor). That way when the weapon slot is at the character’s origin, the “hold point” of the sword lines up with the character.

If your character art uses a different scale (e.g. 512 px tall), scale the sword proportionally so it doesn’t look tiny or huge next to the body.

---

## 3. Where to put the files

| Type        | Folder                              | Example file           | Sprite Library category |
|------------|--------------------------------------|------------------------|--------------------------|
| Main-hand  | `Assets/Characters/Parts/Weapon/`   | `iron_sword.png`       | `Weapon`                 |
| Off-hand   | `Assets/Characters/Parts/Shield/`   | `wooden_shield.png`    | `Shield`                 |
| Armor      | `Assets/Characters/Parts/Armor/`    | `leather_armor.png`    | `Chest`, `Legs`, etc.    |

- The **label** in the manifest / Sprite Library is the **filename without extension** (e.g. `iron_sword`). The game equips by **item id**; the item id in `items.json` must match that label so the correct sprite is shown.

---

## 4. How the sword attaches in-game

1. **Rig slot:** The character rig has a slot named **Weapon** (main hand) and **Shield** (off-hand). Their **SpriteResolver** categories are `Weapon` and `Shield`. Either slot can show a weapon or shield sprite depending on what’s equipped (e.g. dual-wield weapons or weapon + shield in either hand).
2. **Equip flow:** When the player equips an item (e.g. Iron Sword) to Main Hand or Off-hand, the game:
   - Finds the **SpriteResolver** for that hand (Main Hand → `Weapon`, Off-hand → `Shield`).
   - Sets that resolver’s **label** to the item’s **id** (e.g. `iron_sword`).
3. **Sprite Library:** The Sprite Library must have categories `Weapon` and `Shield`, each with labels for every equippable weapon or shield (e.g. `iron_sword`, `wooden_shield`). So the same sword can be shown in either hand; the sprite is chosen by the equipped item’s id. That is filled from the **parts manifest**.
4. **Position:** The Weapon and Shield slots are children of the character’s Slots root, at **local position (0,0)** by default. The sprite’s **pivot** (e.g. bottom center) is the attachment point. Use **Slot Offsets** on the Character Customizer (Alignment → Slot Offsets) if you need to nudge the item left/right/up/down.

So: **same pivot and slot position for all weapons** (e.g. bottom center), and the art is drawn so the “grip” is at that pivot. No extra code is needed for attachment beyond the existing equip + SpriteResolver + Sprite Library pipeline.

---

## 5. After adding or changing art

1. **Tools → Character → Build Parts Manifest** – so the new PNGs appear in `parts_manifest.json` under the right category (Weapon, Shield, Armor, etc.).
2. **Tools → Character → Populate Sprite Library** – so the rig’s Sprite Library gets the new labels (e.g. `Weapon` → `iron_sword_front`, `iron_sword_side`). **You must run this for weapon/armor images to show in-game or in the inventory.**

Then ensure your item is defined in `weapons.json` or `armor.json` (see README_ItemsWeaponsArmor.md) with matching `frontImage`/`sideImage` labels if you use per-facing sprites. Equipping that item will then show your sword/armor on the character.

---

## 6. Summary for “iron sword” first asset

| Question              | Answer |
|-----------------------|--------|
| How many images?      | Start with **one** (`iron_sword.png`). Add front/side/back later if you want per-facing art. |
| Canvas size?          | **256×256** or **128×256**. |
| How big the sword?    | ~100–200 px blade height; grip at bottom center. |
| Pivot?                | **Bottom Center** (0.5, 0). |
| Where to put the file? | `Assets/Characters/Parts/Weapon/iron_sword.png` (or Shield for shields; either hand can show weapon or shield) |
| How does it attach?   | Item id (e.g. `iron_sword`) → SpriteResolver for the equipped hand (Weapon = main hand, Shield = off-hand); label = item id or front/side label; Sprite Library must have that label in both Weapon and Shield categories so it can show in either hand. |

---

## 7. Not seeing weapon/armor images?

- **Run Tools → Character → Populate Sprite Library** (after Build Parts Manifest). The rig’s Sprite Library asset is empty until you run this; without it, equipped weapons/armor and inventory icons will not show.
- In the Console you should see: `[SpriteLibrary] Populated ... N label(s) added`.
- If sprites still don’t appear, confirm the PNGs are under `Assets/Characters/Parts/Weapon/` (or Shield/Armor) and that `parts_manifest.json` lists them under the correct category.

---

## 8. Per-facing offset and rotation (where to add)

**Preferred: in weapons.json / armor.json** – Add **`equipmentOffsets`** to each weapon or armor so different items (e.g. sword vs staff) can have different positions and rotations:

```json
"equipmentOffsets": {
  "front": { "x": 0.2, "y": 0.05, "rotation": -25 },
  "side":  { "x": 0.25, "y": 0.02, "rotation": -15 },
  "back":  { "x": 0.15, "y": -0.02, "rotation": -40 }
}
```

Order of precedence: (1) per-item overrides from JSON, (2) Character Customizer **Equipment Facing Overrides** in the Inspector, (3) built-in defaults. When the character faces left, `x` and `rotation` are mirrored so the item stays in the same hand. Main hand draws behind when facing left; off hand draws behind when facing right.

**Tuning in Unity:** On the **Character Customizer** component, uncheck **Apply Equipment Transforms**. Enter Play mode, equip a weapon, then select the **Weapon** (or **Shield**) child under the player’s **Slots** and move/rotate it in the Scene or Inspector. The values will no longer be overwritten. Copy the Transform’s **Position** (X, Y) and **Rotation** (Z) into your JSON `equipmentOffsets` for the matching facing, then re-check **Apply Equipment Transforms**.
