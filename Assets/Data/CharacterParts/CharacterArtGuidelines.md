# Character Part Art Guidelines

For **weapons and armor** (e.g. iron sword, leather armor), see **[WeaponArmorArtGuide.md](WeaponArmorArtGuide.md)** (canvas size, pivot, how equipping attaches sprites to the character).

## Alignment (Body, Top, Bottom)

If Body, Top, and Bottom appear **misaligned or overlapping** in character creation or in-game:

### 1. Fix at the source (recommended)

- Use the **same pivot** for all Body, Top, and Bottom sprites (e.g. **Bottom Center** `(0.5, 0)` in Unity’s Sprite Editor / Texture Import).
- Use the **same canvas size** (e.g. 256×512) for all three so the character occupies the same area.
- Draw so the **waist** is at the **same Y pixel** in all three images. Top’s bottom edge and Bottom’s top edge should meet at that line.

Use the same canvas size (e.g. 512x512). Re-import and set pivots in Texture Import. In character creation, tune **Preview Waist Y** on Character Creation Bootstrap if the seam is still off.

### 2. Nudge in Unity (quick fix)

On the **player rig** (or character creation preview rig), the **Character Customizer** component has an **Alignment** section:

- Add entries to **Slot Offsets**:
  - **Slot Name**: `Top` or `Bottom` (exact name from the rig).
  - **Offset**: e.g. `(0, 0.2)` to move Top up, `(0, -0.1)` to move Bottom down.

Offsets are applied in local space; adjust until the parts line up.

## Facing in-game

The character’s facing (Front / Back / Side) updates when you move. Moving left uses the same “right” sprite with horizontal flip. No extra art is needed for left.

---

## Walking animations

### Where to store walk frames

Use the **same folder structure** as idle art:

| Part   | Folder                                | Example filenames |
|--------|---------------------------------------|-------------------|
| Body   | `Assets/Characters/Parts/Body/Human/` | `body_human_male_front_walk_01.png`, `body_human_male_front_walk_02.png`, … |
| Top    | `Assets/Characters/Parts/Top/`       | `top_human_male_front_walk_01.png`, `top_human_male_front_walk_02.png`, … |
| Bottom | `Assets/Characters/Parts/Bottom/`    | `bottom_human_male_front_walk_01.png`, `bottom_human_male_front_walk_02.png`, … |

Yes, you need **separate images for Top and Bottom** (and optionally Body) so each slot can animate. Use the same alignment and pivot as your idle art.

### Naming

- **Direction**: `_front_`, `_back_`, or `_right_` in the filename (left = flip of right in-game).
- **Variant**: `_walk_01`, `_walk_02`, `_walk_03`, … for each frame.
- **Examples**: `body_human_male_front_walk_01.png`, `top_human_male_right_walk_02.png`, `bottom_human_male_back_walk_01.png`.

### After adding files

1. **Tools → Character → Build Parts Manifest** (so new sprites are in the manifest).
2. **Tools → Character → Populate Sprite Library** (so the rig can use them).

To play walk frames in-game: add the **Character Walk Animator** component to the player rig (same GameObject as Character Customizer). Configure **Walk Frame Count** (e.g. 4) and **Walk Fps** (e.g. 8). When the character moves, Body/Top/Bottom will cycle through `_walk_01`, `_walk_02`, etc.; when still, idle (`_01`) is shown.
