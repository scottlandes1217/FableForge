using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.U2D.Animation;
#if UNITY_EDITOR
using UnityEditor;
#endif

[Serializable]
public struct SlotOffset
{
    public string slotName;
    public Vector2 offset;
    /// <summary>Rotation in degrees around Z (0 = no change). E.g. -45 for a sword tilted forward.</summary>
    [Tooltip("Rotation in degrees around Z. E.g. -30 for sword tilted forward, 0 for straight up.")]
    public float rotationDegrees;
}

/// <summary>Per-facing offset and rotation for Weapon/Shield. When character faces left (flipX), offset X and rotation are mirrored so the item stays in the same hand.</summary>
[Serializable]
public struct SlotFacingOverride
{
    [Tooltip("Weapon or Shield")]
    public string slotName;
    public FacingDirection facing;
    public Vector2 offset;
    [Tooltip("Rotation in degrees around Z.")]
    public float rotationDegrees;
}

public class CharacterCustomizer : MonoBehaviour
{
    [Header("Preset Sources")]
    [SerializeField] private string presetResourcePath = "CharacterPresets/preset_default";
    [SerializeField] private string presetStreamingFile = "CharacterPresets/preset_default.json";

    [Header("Tint Groups")]
    [SerializeField] private List<SpriteTintGroup> tintGroups = new List<SpriteTintGroup>();

    [Header("Facing")]
    [SerializeField] private FacingDirection defaultFacing = FacingDirection.Front;
    [SerializeField] private FacingDirectionResolver facingResolver;

    [Header("Alignment (Top + Bottom stacked exactly, same position)")]
    [Tooltip("Offset to shift Top and Bottom together (e.g. X = -2 to move character left if art is right-of-center in 512x512).")]
    [SerializeField] private Vector2 characterOffset = Vector2.zero;
    [Tooltip("Override per-slot positions. If empty, Top and Bottom are placed at the same position (characterOffset) so they layer exactly.")]
    [SerializeField] private List<SlotOffset> slotOffsets = new List<SlotOffset>();
    [Header("Equipment per-facing (Weapon/Shield)")]
    [Tooltip("If unchecked, weapon/shield slot position and rotation are not overwritten — use this in the Editor to drag the Weapon/Shield transforms and read the values for your JSON equipmentOffsets. Re-check when done.")]
    [SerializeField] private bool applyEquipmentTransforms = true;
    [Tooltip("Optional Inspector overrides. Per-item overrides from weapons.json/armor.json (equipmentOffsets) take precedence when set; then these; then built-in defaults.")]
    [SerializeField] private List<SlotFacingOverride> equipmentFacingOverrides = new List<SlotFacingOverride>();

    private CharacterPreset activePreset;
    private List<SlotFacingOverride> equippedWeaponOverridesFromItem;
    private List<SlotFacingOverride> equippedShieldOverridesFromItem;
    private string equippedWeaponId;
    private string equippedShieldId;
    private string equippedWeaponFrontLabel;
    private string equippedWeaponSideLabel;
    private string equippedShieldFrontLabel;
    private string equippedShieldSideLabel;

    /// <summary>Current preset slots (Body, Top, Bottom, etc.) used for facing and walk frame base labels.</summary>
    public Dictionary<string, string> ActivePresetSlots => activePreset?.slots;

    /// <summary>Preset slots merged with equipped weapon/shield. Use this for SetFacing so the equipped item stays visible.</summary>
    public Dictionary<string, string> GetSlotsForFacing()
    {
        return BuildSlotsWithEquipped(ActivePresetSlots);
    }

    /// <summary>Set the equipped item id for Weapon (main hand) or Shield (off hand). Called when equipping/unequipping. Pass null to clear.</summary>
    public void SetEquippedItemId(string slotCategory, string itemId)
    {
        if (string.Equals(slotCategory, "Weapon", StringComparison.OrdinalIgnoreCase))
        {
            equippedWeaponId = itemId;
            if (string.IsNullOrEmpty(itemId)) { equippedWeaponFrontLabel = null; equippedWeaponSideLabel = null; equippedWeaponOverridesFromItem = null; }
        }
        else if (string.Equals(slotCategory, "Shield", StringComparison.OrdinalIgnoreCase))
        {
            equippedShieldId = itemId;
            if (string.IsNullOrEmpty(itemId)) { equippedShieldFrontLabel = null; equippedShieldSideLabel = null; equippedShieldOverridesFromItem = null; }
        }
    }

    /// <summary>Get the equipped item id for Weapon or Shield. Returns null if none equipped.</summary>
    public string GetEquippedItemId(string slotCategory)
    {
        if (string.Equals(slotCategory, "Weapon", StringComparison.OrdinalIgnoreCase))
            return equippedWeaponId;
        if (string.Equals(slotCategory, "Shield", StringComparison.OrdinalIgnoreCase))
            return equippedShieldId;
        return null;
    }

    /// <summary>Set per-facing offset/rotation from the equipped item's JSON (weapons.json/armor.json equipmentOffsets). Pass null to clear. Takes precedence over Inspector overrides and defaults.</summary>
    public void SetEquippedItemEquipmentOverrides(string slotCategory, List<SlotFacingOverride> overrides)
    {
        if (string.Equals(slotCategory, "Weapon", StringComparison.OrdinalIgnoreCase))
            equippedWeaponOverridesFromItem = overrides;
        else if (string.Equals(slotCategory, "Shield", StringComparison.OrdinalIgnoreCase))
            equippedShieldOverridesFromItem = overrides;
    }

    /// <summary>Set sprite labels for equipped weapon/shield so the correct front/side sprite can be shown when facing changes.</summary>
    public void SetEquippedItemLabels(string slotCategory, string frontLabel, string sideLabel)
    {
        if (string.Equals(slotCategory, "Weapon", StringComparison.OrdinalIgnoreCase))
        {
            equippedWeaponFrontLabel = frontLabel;
            equippedWeaponSideLabel = sideLabel;
        }
        else if (string.Equals(slotCategory, "Shield", StringComparison.OrdinalIgnoreCase))
        {
            equippedShieldFrontLabel = frontLabel;
            equippedShieldSideLabel = sideLabel;
        }
    }

    /// <summary>Apply the correct weapon/shield sprite for current facing. Call after SetFacing when movement or walk animator runs.</summary>
    public void RefreshEquipmentSprites()
    {
        var slotsRoot = transform.Find("Slots");
        if (slotsRoot == null) return;
        if (spriteLibrary == null) spriteLibrary = GetComponentInParent<SpriteLibrary>();
        if (spriteLibrary == null || spriteLibrary.spriteLibraryAsset == null) return;
        var facingResolver = GetComponent<FacingDirectionResolver>();
        var isSide = facingResolver != null && facingResolver.CurrentFacing == FacingDirection.Side;

        var weaponSlot = slotsRoot.Find("Weapon");
        var shieldSlot = slotsRoot.Find("Shield");

        if (!string.IsNullOrEmpty(equippedWeaponFrontLabel) || !string.IsNullOrEmpty(equippedWeaponSideLabel))
        {
            var label = isSide ? (equippedWeaponSideLabel ?? equippedWeaponFrontLabel) : (equippedWeaponFrontLabel ?? equippedWeaponSideLabel);
            if (!string.IsNullOrEmpty(label))
            {
                var sprite = spriteLibrary.spriteLibraryAsset.GetSprite("Weapon", label);
                if (sprite != null && weaponSlot != null)
                {
                    var r = weaponSlot.GetComponent<SpriteRenderer>();
                    if (r != null) { r.sprite = sprite; r.enabled = true; }
                }
            }
        }
        else if (weaponSlot != null)
        {
            var r = weaponSlot.GetComponent<SpriteRenderer>();
            if (r != null) r.enabled = false;
        }

        if (!string.IsNullOrEmpty(equippedShieldFrontLabel) || !string.IsNullOrEmpty(equippedShieldSideLabel))
        {
            var label = isSide ? (equippedShieldSideLabel ?? equippedShieldFrontLabel) : (equippedShieldFrontLabel ?? equippedShieldSideLabel);
            if (!string.IsNullOrEmpty(label))
            {
                var sprite = spriteLibrary.spriteLibraryAsset.GetSprite("Shield", label);
                if (sprite != null && shieldSlot != null)
                {
                    var r = shieldSlot.GetComponent<SpriteRenderer>();
                    if (r != null) { r.sprite = sprite; r.enabled = true; }
                }
            }
        }
        else if (shieldSlot != null)
        {
            var r = shieldSlot.GetComponent<SpriteRenderer>();
            if (r != null) r.enabled = false;
        }

        HideEmptySlotRenderers(slotsRoot);
    }

    /// <summary>Disable any slot SpriteRenderer with no sprite so empty slots don't show as white quads.</summary>
    private void HideEmptySlotRenderers(Transform slotsRoot)
    {
        if (slotsRoot == null) return;
        for (var i = 0; i < slotsRoot.childCount; i++)
        {
            var slot = slotsRoot.GetChild(i);
            var r = slot.GetComponent<SpriteRenderer>();
            if (r == null)
            {
                continue;
            }

            if (r.sprite == null)
            {
                r.enabled = false;
                continue;
            }

            if (string.Equals(r.sprite.name, "placeholder", StringComparison.OrdinalIgnoreCase))
            {
                r.enabled = false;
            }
        }
    }

    /// <summary>Apply per-facing position, rotation, and sorting order for Weapon and Shield. Call when facing or flipX changes. When flipX (facing left), offset X and rotation are mirrored so the item stays in the same hand. Main hand (Weapon) is behind when facing left; off hand (Shield) is behind when facing right. Skipped when applyEquipmentTransforms is false (e.g. to tune in Editor).</summary>
    public void ApplyEquipmentSlotTransforms(FacingDirection direction, bool flipX)
    {
        if (!applyEquipmentTransforms) return;
        var slotsRoot = transform.Find("Slots");
        if (slotsRoot == null) return;

        int baseOrder = GameSceneController.PlayerSortingBaseOrder;
        if (baseOrder < 0) baseOrder = 0;
        int orderInFront = baseOrder + 5;
        int orderBehind = baseOrder - 2;

        ApplyOneEquipmentSlot(slotsRoot, "Weapon", direction, flipX, orderInFront, orderBehind);
        ApplyOneEquipmentSlot(slotsRoot, "Shield", direction, flipX, orderInFront, orderBehind);
    }

    private void ApplyOneEquipmentSlot(Transform slotsRoot, string slotName, FacingDirection direction, bool flipX, int orderInFront, int orderBehind)
    {
        var slot = slotsRoot.Find(slotName);
        if (slot == null) return;

        Vector2 offset;
        float rotationDegrees;
        if (TryGetEquipmentFacingOverride(slotName, direction, out offset, out rotationDegrees))
        {
            // use override
        }
        else
        {
            GetDefaultEquipmentFacing(slotName, direction, out offset, out rotationDegrees);
        }

        if (flipX)
        {
            offset.x = -offset.x;
            rotationDegrees = -rotationDegrees;
        }

        slot.localPosition = new Vector3(offset.x, offset.y, 0f);
        slot.localEulerAngles = new Vector3(0f, 0f, rotationDegrees);

        bool inFront = GetEquipmentSortInFront(slotName, direction, flipX);
        var r = slot.GetComponent<SpriteRenderer>();
        if (r != null)
            r.sortingOrder = inFront ? orderInFront : orderBehind;
    }

    /// <summary>Main hand (Weapon): in front when facing front or side-right; behind when back or side-left. Off hand (Shield): opposite for side (in front when side-left, behind when side-right).</summary>
    private static bool GetEquipmentSortInFront(string slotName, FacingDirection direction, bool flipX)
    {
        if (direction == FacingDirection.Front) return true;
        if (direction == FacingDirection.Back) return false;
        if (string.Equals(slotName, "Weapon", StringComparison.OrdinalIgnoreCase))
            return !flipX;
        if (string.Equals(slotName, "Shield", StringComparison.OrdinalIgnoreCase))
            return flipX;
        return true;
    }

    private bool TryGetEquipmentFacingOverride(string slotName, FacingDirection facing, out Vector2 offset, out float rotationDegrees)
    {
        offset = Vector2.zero;
        rotationDegrees = 0f;
        var fromItem = string.Equals(slotName, "Weapon", StringComparison.OrdinalIgnoreCase) ? equippedWeaponOverridesFromItem : equippedShieldOverridesFromItem;
        if (fromItem != null)
        {
            foreach (var o in fromItem)
            {
                if (o.facing == facing)
                {
                    offset = o.offset;
                    rotationDegrees = o.rotationDegrees;
                    return true;
                }
            }
        }
        if (equipmentFacingOverrides != null)
        {
            foreach (var o in equipmentFacingOverrides)
            {
                if (string.Equals(o.slotName, slotName, StringComparison.OrdinalIgnoreCase) && o.facing == facing)
                {
                    offset = o.offset;
                    rotationDegrees = o.rotationDegrees;
                    return true;
                }
            }
        }
        return false;
    }

    private static void GetDefaultEquipmentFacing(string slotName, FacingDirection facing, out Vector2 offset, out float rotationDegrees)
    {
        if (string.Equals(slotName, "Weapon", StringComparison.OrdinalIgnoreCase))
        {
            switch (facing)
            {
                case FacingDirection.Front: offset = new Vector2(-0.55f, 0.5f); rotationDegrees = -13f; return;
                case FacingDirection.Side: offset = new Vector2(0.19f, 0.1f); rotationDegrees = -55f; return;
                case FacingDirection.Back: offset = new Vector2(0.45f, 0.3f); rotationDegrees = 24f; return;
                default: offset = new Vector2(0.2f, 0.05f); rotationDegrees = -25f; return;
            }
        }
        if (string.Equals(slotName, "Shield", StringComparison.OrdinalIgnoreCase))
        {
            switch (facing)
            {
                case FacingDirection.Front: offset = new Vector2(-0.55f, 0.5f); rotationDegrees = -13f; return;
                case FacingDirection.Side: offset = new Vector2(0.19f, 0.1f); rotationDegrees = -55f; return;
                case FacingDirection.Back: offset = new Vector2(0.45f, 0.3f); rotationDegrees = 24f; return;
                default: offset = new Vector2(-0.2f, 0.05f); rotationDegrees = 10f; return;
            }
        }
        offset = Vector2.zero;
        rotationDegrees = 0f;
    }

    private SpriteLibrary spriteLibrary;
    private static Dictionary<string, string> manifestSpriteLookup;
    private static bool manifestLoaded;

    // Same logic as character preview: resolve labels per facing (body_right, eyes_side_round_01, etc.)
    private static readonly HashSet<string> SlotsThatDontUseFacingVariants = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "HairFront", "HairBack", "HairSide", "Head",
        "Weapon", "Shield"
    };
    private static readonly HashSet<string> FaceSlotCategories = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "Eyes", "Eyebrows", "Mouth", "Nose"
    };

    private void Start()
    {
        if (activePreset == null)
        {
            LoadAndApplyPreset();
        }
    }

    public void ApplyPreset(CharacterPreset preset)
    {
        if (preset == null)
        {
            return;
        }

        activePreset = preset;
        ApplySlots(preset.slots);
        ApplyFacing(preset.slots);
        ApplySlotOffsets();
        ApplyTints(preset.tints);
        HideBodySlot();
        RefreshEquipmentSprites();
    }

    /// <summary>
    /// Body assets are kept but not displayed; Top + Bottom provide full coverage.
    /// </summary>
    private void HideBodySlot()
    {
        var slotsRoot = transform.Find("Slots");
        if (slotsRoot == null)
        {
            return;
        }

        var body = slotsRoot.Find("Body");
        if (body != null)
        {
            var renderer = body.GetComponent<SpriteRenderer>();
            if (renderer != null)
            {
                renderer.enabled = false;
            }
        }
    }

    /// <summary>
    /// Call from movement: updates facing (Front/Back/Side) and flip for left based on last movement input.
    /// </summary>
    public void SetFacingFromMovement(Vector2 lastMovementInput)
    {
        if (activePreset == null || activePreset.slots == null || activePreset.slots.Count == 0)
        {
            return;
        }

        if (facingResolver == null)
        {
            facingResolver = GetComponent<FacingDirectionResolver>();
        }
        if (facingResolver == null)
        {
            facingResolver = gameObject.AddComponent<FacingDirectionResolver>();
        }

        var direction = FacingDirection.Front;
        var flipForLeft = false;

        if (lastMovementInput.sqrMagnitude > 0.01f)
        {
            if (lastMovementInput.y > 0.2f)
            {
                direction = FacingDirection.Back;
            }
            else if (lastMovementInput.y < -0.2f)
            {
                direction = FacingDirection.Front;
            }
            else if (Mathf.Abs(lastMovementInput.x) > 0.2f)
            {
                direction = FacingDirection.Side;
                flipForLeft = lastMovementInput.x < 0f;
            }
        }
        else
        {
            direction = facingResolver.CurrentFacing;
        }

        var slotsForFacing = BuildSlotsWithEquipped(activePreset.slots);
        facingResolver.SetFacing(direction, slotsForFacing);

        // Same as preview: apply resolved sprites from manifest so body/top/bottom/face match facing
        var resolvedSlots = BuildResolvedSlotsForFacing(slotsForFacing, direction);
        ApplyResolvedSlotsFromManifest(resolvedSlots);
        facingResolver.ApplyHairVisibilityOnly();
        RefreshEquipmentSprites();
        ApplyEquipmentSlotTransforms(direction, flipForLeft);

        var renderers = GetComponentsInChildren<SpriteRenderer>(true);
        foreach (var r in renderers)
        {
            if (r != null)
            {
                r.flipX = (direction == FacingDirection.Side && flipForLeft);
            }
        }
    }

    private Dictionary<string, string> BuildSlotsWithEquipped(Dictionary<string, string> baseSlots)
    {
        var merged = baseSlots != null ? new Dictionary<string, string>(baseSlots) : new Dictionary<string, string>();
        if (!string.IsNullOrEmpty(equippedWeaponId))
            merged["Weapon"] = equippedWeaponId;
        if (!string.IsNullOrEmpty(equippedShieldId))
            merged["Shield"] = equippedShieldId;
        return merged;
    }

    /// <summary>Same logic as character preview: resolve slot labels for current facing (front/back/right, face _side_).</summary>
    public Dictionary<string, string> BuildResolvedSlotsForFacing(Dictionary<string, string> baseSlots, FacingDirection facing)
    {
        var result = new Dictionary<string, string>();
        if (baseSlots == null)
        {
            return result;
        }

        var suffix = facing == FacingDirection.Back ? "back" : (facing == FacingDirection.Side ? "right" : "front");
        foreach (var entry in baseSlots)
        {
            var label = entry.Value ?? "";
            if (!string.IsNullOrWhiteSpace(label) && !SlotsThatDontUseFacingVariants.Contains(entry.Key))
            {
                if (FaceSlotCategories.Contains(entry.Key) && facing == FacingDirection.Side)
                {
                    var firstUnderscore = label.IndexOf('_');
                    if (firstUnderscore > 0)
                        label = label.Substring(0, firstUnderscore) + "_side_" + label.Substring(firstUnderscore + 1);
                    else
                        label = label + "_side";
                }
                else if (label.Contains("_front_")) label = label.Replace("_front_", $"_{suffix}_");
                else if (label.Contains("_back_")) label = label.Replace("_back_", $"_{suffix}_");
                else if (label.Contains("_right_")) label = label.Replace("_right_", $"_{suffix}_");
                else if (label.Contains("_side_")) label = label.Replace("_side_", $"_{suffix}_");
                else if (suffix != "front") label = $"{label}_{suffix}";
            }
            result[entry.Key] = label;
        }
        return result;
    }

    /// <summary>Apply resolved slot sprites from manifest (same as preview ApplyManifestSpriteOverride). Call after SetFacing so body/top/bottom/face match direction.</summary>
    public void ApplyResolvedSlotsFromManifest(Dictionary<string, string> slots)
    {
        if (slots == null)
        {
            return;
        }

        var slotsRoot = transform.Find("Slots");
        if (slotsRoot == null)
        {
            return;
        }

        // Hair: assign correct sprite to each slot by name
        if (slots.TryGetValue("HairFront", out var frontLabel) && !string.IsNullOrWhiteSpace(frontLabel))
        {
            var s = TryLoadSpriteFromManifest("HairFront", frontLabel);
            if (s != null) ApplySpriteToSlot(slotsRoot.Find("HairFront"), s);
        }
        if (slots.TryGetValue("HairBack", out var backLabel) && !string.IsNullOrWhiteSpace(backLabel))
        {
            var s = TryLoadSpriteFromManifest("HairBack", backLabel);
            if (s != null) ApplySpriteToSlot(slotsRoot.Find("HairBack"), s);
        }
        if (slots.TryGetValue("HairSide", out var sideLabel) && !string.IsNullOrWhiteSpace(sideLabel))
        {
            var s = TryLoadSpriteFromManifest("HairSide", sideLabel);
            if (s != null) ApplySpriteToSlot(slotsRoot.Find("HairSide"), s);
        }

        foreach (var entry in slots)
        {
            if (string.IsNullOrWhiteSpace(entry.Key) || string.IsNullOrWhiteSpace(entry.Value))
                continue;
            if (string.Equals(entry.Key, "Body", StringComparison.OrdinalIgnoreCase))
                continue;
            if (string.Equals(entry.Key, "HairFront", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(entry.Key, "HairBack", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(entry.Key, "HairSide", StringComparison.OrdinalIgnoreCase))
                continue;
            if (string.Equals(entry.Value, "placeholder", StringComparison.OrdinalIgnoreCase))
                continue;

            var sprite = TryLoadSpriteFromManifest(entry.Key, entry.Value);
            if (sprite == null)
                continue;

            ApplySpriteToSlotByCategory(entry.Key, sprite);
        }

        ApplySlotSortOrder(slotsRoot);
    }

    private static void ApplySpriteToSlot(Transform slot, Sprite sprite)
    {
        if (slot == null || sprite == null) return;
        var r = slot.GetComponent<SpriteRenderer>();
        if (r != null)
        {
            r.sprite = sprite;
            r.enabled = !string.Equals(slot.name, "Body", StringComparison.OrdinalIgnoreCase);
        }
        var resolver = slot.GetComponent<SpriteResolver>();
        if (resolver != null)
            resolver.enabled = false;
    }

    private void ApplySpriteToSlotByCategory(string category, Sprite sprite)
    {
        var slotsRoot = transform.Find("Slots");
        if (slotsRoot == null) return;
        var slot = slotsRoot.Find(category);
        if (slot != null)
            ApplySpriteToSlot(slot, sprite);
    }

    public void LoadAndApplyPreset()
    {
        var preset = LoadPreset();
        if (preset == null)
        {
            Debug.LogWarning("CharacterCustomizer: No preset found.");
            return;
        }

        ApplyPreset(preset);
    }

    private CharacterPreset LoadPreset()
    {
        if (!string.IsNullOrWhiteSpace(presetResourcePath))
        {
            var textAsset = Resources.Load<TextAsset>(presetResourcePath);
            if (textAsset != null)
            {
                return CharacterPreset.FromJson(textAsset.text);
            }
        }

        if (!string.IsNullOrWhiteSpace(presetStreamingFile))
        {
            var path = Path.Combine(Application.streamingAssetsPath, presetStreamingFile);
            if (File.Exists(path))
            {
                var json = File.ReadAllText(path);
                return CharacterPreset.FromJson(json);
            }
        }

        return null;
    }

    private void ApplySlots(Dictionary<string, string> slots)
    {
        if (slots == null || slots.Count == 0)
        {
            return;
        }

        if (spriteLibrary == null)
        {
            spriteLibrary = GetComponentInParent<SpriteLibrary>();
        }

        var hasLibrary = HasSpriteLibraryEntries(spriteLibrary);
        var appliedCategories = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        // For hair slots, match by GameObject name so we apply the correct sprite even if the rig's
        // SpriteResolver category is swapped (e.g. HairFront object has category "HairBack").
        var resolvers = GetComponentsInChildren<SpriteResolver>(true);
        foreach (var resolver in resolvers)
        {
            if (resolver == null)
            {
                continue;
            }

            var category = resolver.GetCategory();
            if (string.IsNullOrWhiteSpace(category))
            {
                category = resolver.gameObject.name;
                if (!string.IsNullOrWhiteSpace(category) && hasLibrary)
                {
                    resolver.SetCategoryAndLabel(category, "placeholder");
                }
            }

            var slotKey = category;
            var slotName = resolver.gameObject.name;
            if (string.Equals(slotName, "HairFront", StringComparison.OrdinalIgnoreCase)
                || string.Equals(slotName, "HairBack", StringComparison.OrdinalIgnoreCase)
                || string.Equals(slotName, "HairSide", StringComparison.OrdinalIgnoreCase))
            {
                slotKey = slotName;
            }

            if (!slots.TryGetValue(slotKey, out var label) || string.IsNullOrWhiteSpace(label))
            {
                continue;
            }

            appliedCategories.Add(slotKey);

            if (hasLibrary)
            {
                resolver.SetCategoryAndLabel(slotKey, label);
                continue;
            }

            var manifestSprite = TryLoadSpriteFromManifest(slotKey, label);
            if (manifestSprite != null)
            {
                var renderer = resolver.GetComponent<SpriteRenderer>();
                if (renderer != null)
                {
                    resolver.enabled = false;
                    renderer.sprite = manifestSprite;
                    // Body is never displayed; Top + Bottom provide full coverage.
                    renderer.enabled = !string.Equals(slotKey, "Body", System.StringComparison.OrdinalIgnoreCase);
                }
            }
        }

        // Create missing slot GameObjects (e.g. Eyes, Eyebrows, Mouth) so presets can add parts the rig doesn't have yet
        var slotsRoot = FindChildRecursive(transform, "Slots");
        if (slotsRoot == null)
        {
            return;
        }

        foreach (var kvp in slots)
        {
            var category = kvp.Key;
            var label = kvp.Value;
            if (string.IsNullOrWhiteSpace(category) || string.IsNullOrWhiteSpace(label) || appliedCategories.Contains(category))
            {
                continue;
            }

            var slotTransform = EnsureSlotExists(slotsRoot, category, label);
            if (slotTransform == null)
            {
                continue;
            }

            var resolver = slotTransform.GetComponent<SpriteResolver>();
            var renderer = slotTransform.GetComponent<SpriteRenderer>();
            if (resolver == null || renderer == null)
            {
                continue;
            }

            if (hasLibrary)
            {
                resolver.SetCategoryAndLabel(category, label);
                resolver.enabled = true;
                continue;
            }

            var manifestSprite = TryLoadSpriteFromManifest(category, label);
            if (manifestSprite != null)
            {
                resolver.enabled = false;
                renderer.sprite = manifestSprite;
                renderer.enabled = !string.Equals(category, "Body", System.StringComparison.OrdinalIgnoreCase);
            }
        }
    }

    /// <summary>
    /// Creates a slot GameObject under the Slots root if it doesn't exist (e.g. Eyes, Eyebrows, Mouth),
    /// so we can display parts the rig was not built with. Returns the transform (existing or new).
    /// </summary>
    private Transform EnsureSlotExists(Transform slotsRoot, string category, string label)
    {
        if (slotsRoot == null || string.IsNullOrWhiteSpace(category))
        {
            return null;
        }

        var existing = slotsRoot.Find(category);
        if (existing != null)
        {
            return existing;
        }

        var slotGo = new GameObject(category);
        slotGo.transform.SetParent(slotsRoot, false);
        slotGo.transform.localPosition = Vector3.zero;
        slotGo.transform.localScale = Vector3.one;
        slotGo.transform.localRotation = Quaternion.identity;

        var renderer = slotGo.AddComponent<SpriteRenderer>();
        renderer.sortingOrder = 0;
        renderer.color = Color.white;

        var resolver = slotGo.AddComponent<SpriteResolver>();
        resolver.SetCategoryAndLabel(category, label);

        return slotGo.transform;
    }

    private void ApplySlotOffsets()
    {
        var slotsRoot = transform.Find("Slots");
        if (slotsRoot == null)
        {
            return;
        }

        if (slotOffsets != null && slotOffsets.Count > 0)
        {
            foreach (var entry in slotOffsets)
            {
                if (string.IsNullOrWhiteSpace(entry.slotName))
                {
                    continue;
                }
                // Top and Bottom are always controlled by StackTopBottomAtPosition below.
                if (string.Equals(entry.slotName, "Top", System.StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(entry.slotName, "Bottom", System.StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var slotTransform = slotsRoot.Find(entry.slotName);
                if (slotTransform != null)
                {
                    slotTransform.localPosition = new Vector3(entry.offset.x, entry.offset.y, 0f);
                    slotTransform.localEulerAngles = new Vector3(0f, 0f, entry.rotationDegrees);
                }
            }
        }

        ApplyDefaultEquipmentSlotPositions(slotsRoot);

        // Always stack Top and Bottom at the same position so they overlay correctly.
        StackTopBottomAtPosition(slotsRoot, characterOffset);
        ApplySlotSortOrder(slotsRoot);

        var dir = (facingResolver != null) ? facingResolver.CurrentFacing : defaultFacing;
        ApplyEquipmentSlotTransforms(dir, false);
    }

    /// <summary>Apply default positions/rotations for Weapon and Shield when not in slotOffsets. ApplyEquipmentSlotTransforms (per-facing) overwrites these when facing is applied.</summary>
    private void ApplyDefaultEquipmentSlotPositions(Transform slotsRoot)
    {
        if (slotsRoot == null) return;
        var hasWeaponOffset = slotOffsets != null && slotOffsets.Exists(e => string.Equals(e.slotName, "Weapon", StringComparison.OrdinalIgnoreCase));
        var hasShieldOffset = slotOffsets != null && slotOffsets.Exists(e => string.Equals(e.slotName, "Shield", StringComparison.OrdinalIgnoreCase));
        if (!hasWeaponOffset)
        {
            var weapon = slotsRoot.Find("Weapon");
            if (weapon != null)
            {
                weapon.localPosition = new Vector3(0.2f, 0.05f, 0f);
                weapon.localEulerAngles = new Vector3(0f, 0f, -25f);
            }
        }
        if (!hasShieldOffset)
        {
            var shield = slotsRoot.Find("Shield");
            if (shield != null)
            {
                shield.localPosition = new Vector3(-0.2f, 0.05f, 0f);
                shield.localEulerAngles = new Vector3(0f, 0f, 10f);
            }
        }
    }

    /// <summary>
    /// Same order as character preview: Body behind, then Bottom, Top, then hair and face in front.
    /// Uses GameSceneController.PlayerSortingBaseOrder when in game so the character stays in front of the map (that value is set when the player is spawned). In character creator base is 0.
    /// </summary>
    private void ApplySlotSortOrder(Transform slotsRoot)
    {
        if (slotsRoot == null)
        {
            return;
        }

        int baseOrder = GameSceneController.PlayerSortingBaseOrder;
        if (baseOrder < 0)
            baseOrder = 0;

        var body = slotsRoot.Find("Body");
        var top = slotsRoot.Find("Top");
        var bottom = slotsRoot.Find("Bottom");

        if (body != null)
        {
            var r = body.GetComponent<SpriteRenderer>();
            if (r != null)
                r.sortingOrder = baseOrder - 1;
        }

        if (bottom != null)
        {
            var r = bottom.GetComponent<SpriteRenderer>();
            if (r != null)
                r.sortingOrder = baseOrder;
        }

        if (top != null)
        {
            var r = top.GetComponent<SpriteRenderer>();
            if (r != null)
                r.sortingOrder = baseOrder + 1;
        }

        // Hair and face draw in front of body/top (same order as preview)
        var overlayOrder = baseOrder + 2;
        foreach (var name in new[] { "HairBack", "HairFront", "HairSide", "Nose", "Mouth", "Eyebrows", "Eyes" })
        {
            var slot = slotsRoot.Find(name);
            if (slot != null)
            {
                var r = slot.GetComponent<SpriteRenderer>();
                if (r != null)
                    r.sortingOrder = overlayOrder++;
            }
        }
    }

    /// <summary>
    /// Places Body at origin. Top and Bottom at the exact same local position, scale, and rotation
    /// so they stack directly on top of each other. Art must use the same pivot (e.g. Bottom Center).
    /// </summary>
    private void StackTopBottomAtPosition(Transform slotsRoot, Vector2 userOffset)
    {
        var body = slotsRoot.Find("Body");
        var top = slotsRoot.Find("Top");
        var bottom = slotsRoot.Find("Bottom");

        if (body != null)
        {
            body.localPosition = Vector3.zero;
            body.localScale = Vector3.one;
            body.localRotation = Quaternion.identity;
        }

        var samePos = new Vector3(userOffset.x, userOffset.y, 0f);
        if (top != null)
        {
            top.localPosition = samePos;
            top.localScale = Vector3.one;
            top.localRotation = Quaternion.identity;
        }
        if (bottom != null)
        {
            bottom.localPosition = samePos;
            bottom.localScale = Vector3.one;
            bottom.localRotation = Quaternion.identity;
        }
    }

    private void ApplyTints(Dictionary<string, string> tints)
    {
        if (tints == null || tints.Count == 0)
        {
            return;
        }

        foreach (var group in tintGroups)
        {
            if (group == null || string.IsNullOrWhiteSpace(group.tintKey))
            {
                continue;
            }

            if (tints.TryGetValue(group.tintKey, out var hex) && TryParseHexColor(hex, out var color))
            {
                group.ApplyColor(color);
            }
        }

        // Fallback: apply Skin to Top/Bottom/Head/Body (visible body slots) so skin color persists when loading the game
        if (tints.TryGetValue("Skin", out var skinHex) && TryParseHexColor(skinHex, out var skinColor))
        {
            ApplySkinTintToSlots(skinColor);
        }

        // Fallback: apply Hair tint to Hair and Eyebrows slots so hair/eyebrow color persists when loading the game
        if (tints.TryGetValue("Hair", out var hairHex) && TryParseHexColor(hairHex, out var hairColor))
        {
            ApplyTintToSlotCategories(hairColor, "HairFront", "HairBack", "HairSide", "Eyebrows");
        }
    }

    private void ApplyTintToSlotCategories(Color color, params string[] categories)
    {
        if (categories == null || categories.Length == 0)
        {
            return;
        }

        var resolvers = GetComponentsInChildren<SpriteResolver>(true);
        foreach (var resolver in resolvers)
        {
            if (resolver == null)
            {
                continue;
            }

            var category = resolver.GetCategory();
            if (string.IsNullOrWhiteSpace(category))
            {
                category = resolver.gameObject.name;
            }

            foreach (var target in categories)
            {
                if (!string.Equals(category, target, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var renderer = resolver.GetComponent<SpriteRenderer>();
                if (renderer != null)
                {
                    renderer.color = color;
                }

                break;
            }
        }
    }

    private void ApplySkinTintToSlots(Color skinColor)
    {
        var resolvers = GetComponentsInChildren<SpriteResolver>(true);
        foreach (var resolver in resolvers)
        {
            if (resolver == null) continue;
            var category = resolver.GetCategory();
            if (string.IsNullOrWhiteSpace(category))
            {
                category = resolver.gameObject.name;
            }
            if (string.IsNullOrWhiteSpace(category)) continue;
            var cat = category.Trim();
            var isSkinSlot = string.Equals(cat, "Head", StringComparison.OrdinalIgnoreCase)
                || string.Equals(cat, "Body", StringComparison.OrdinalIgnoreCase)
                || string.Equals(cat, "Top", StringComparison.OrdinalIgnoreCase)
                || string.Equals(cat, "Bottom", StringComparison.OrdinalIgnoreCase)
                || cat.IndexOf("Head", StringComparison.OrdinalIgnoreCase) >= 0
                || cat.IndexOf("Body", StringComparison.OrdinalIgnoreCase) >= 0
                || cat.IndexOf("Top", StringComparison.OrdinalIgnoreCase) >= 0
                || cat.IndexOf("Bottom", StringComparison.OrdinalIgnoreCase) >= 0;
            if (!isSkinSlot) continue;
            var renderer = resolver.GetComponent<SpriteRenderer>();
            if (renderer != null)
            {
                renderer.color = skinColor;
            }
        }

        var slotsRoot = FindChildRecursive(transform, "Slots");
        if (slotsRoot == null) return;
        for (var i = 0; i < slotsRoot.childCount; i++)
        {
            var slot = slotsRoot.GetChild(i);
            var name = slot.name ?? "";
            var isSkin = name.IndexOf("Head", StringComparison.OrdinalIgnoreCase) >= 0
                || name.IndexOf("Body", StringComparison.OrdinalIgnoreCase) >= 0
                || name.IndexOf("Top", StringComparison.OrdinalIgnoreCase) >= 0
                || name.IndexOf("Bottom", StringComparison.OrdinalIgnoreCase) >= 0;
            if (!isSkin) continue;
            foreach (var child in slot.GetComponentsInChildren<SpriteRenderer>(true))
            {
                if (child != null)
                {
                    child.color = skinColor;
                }
            }
        }
    }

    private static Transform FindChildRecursive(Transform parent, string name)
    {
        if (parent == null || string.IsNullOrEmpty(name)) return null;
        var direct = parent.Find(name);
        if (direct != null) return direct;
        for (var i = 0; i < parent.childCount; i++)
        {
            var found = FindChildRecursive(parent.GetChild(i), name);
            if (found != null) return found;
        }
        return null;
    }

    private void ApplyFacing(Dictionary<string, string> slots)
    {
        if (slots == null || slots.Count == 0)
        {
            return;
        }

        if (facingResolver == null)
        {
            facingResolver = GetComponent<FacingDirectionResolver>();
        }

        if (facingResolver == null)
        {
            facingResolver = gameObject.AddComponent<FacingDirectionResolver>();
        }

        facingResolver.SetFacing(defaultFacing, slots);
        var resolvedSlots = BuildResolvedSlotsForFacing(slots, defaultFacing);
        ApplyResolvedSlotsFromManifest(resolvedSlots);
        facingResolver.ApplyHairVisibilityOnly();
    }

    private bool HasSpriteLibraryEntries(SpriteLibrary library)
    {
        if (library == null || library.spriteLibraryAsset == null)
        {
            return false;
        }

        try
        {
            foreach (var _ in library.spriteLibraryAsset.GetCategoryNames())
            {
                return true;
            }
        }
        catch (Exception)
        {
            return false;
        }

        return false;
    }

    private Sprite TryLoadSpriteFromManifest(string category, string label)
    {
        if (string.IsNullOrWhiteSpace(category) || string.IsNullOrWhiteSpace(label))
        {
            return null;
        }

        EnsureManifestLookup();
        if (manifestSpriteLookup == null)
        {
            return null;
        }

        var lookupKey = $"{category}|{label}";
        if (!manifestSpriteLookup.TryGetValue(lookupKey, out var assetPath))
        {
            // Fallback for hair: if exact style (e.g. Long, Braided) isn't in manifest, use Short so hair still shows
            if (string.Equals(category, "HairFront", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(category, "HairBack", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(category, "HairSide", StringComparison.OrdinalIgnoreCase))
            {
                var fallbackLabel = category.Trim().ToLowerInvariant() switch
                {
                    "hairfront" => "hair_front_short_01",
                    "hairback" => "hair_back_short_01",
                    "hairside" => "hair_side_short_01",
                    _ => null
                };
                if (!string.IsNullOrEmpty(fallbackLabel))
                {
                    var fallbackKey = $"{category}|{fallbackLabel}";
                    manifestSpriteLookup.TryGetValue(fallbackKey, out assetPath);
                }
            }

            // Face side variant missing? Use front sprite (e.g. eyes_side_round_01 -> eyes_round_01)
            if (assetPath == null && label != null && label.Contains("_side_"))
            {
                var frontLabel = label.Replace("_side_", "_");
                var frontKey = $"{category}|{frontLabel}";
                if (manifestSpriteLookup.TryGetValue(frontKey, out assetPath))
                {
                    lookupKey = frontKey;
                }
            }

            if (assetPath == null)
            {
                return null;
            }
        }

        return LoadSpriteAtPath(assetPath);
    }

    private void EnsureManifestLookup()
    {
        if (manifestLoaded)
        {
            return;
        }

        manifestLoaded = true;
        manifestSpriteLookup = new Dictionary<string, string>();

        var manifestPath = Path.Combine(Application.dataPath, "Data/CharacterParts/parts_manifest.json");
        string json = null;
        if (File.Exists(manifestPath))
        {
            json = File.ReadAllText(manifestPath);
        }
        else
        {
            var textAsset = Resources.Load<TextAsset>("Data/CharacterParts/parts_manifest");
            if (textAsset != null)
            {
                json = textAsset.text;
            }
        }

        if (string.IsNullOrWhiteSpace(json))
        {
            return;
        }

        var parsed = MiniJson.Deserialize(json) as Dictionary<string, object>;
        if (parsed == null || !parsed.TryGetValue("categories", out var categoriesObj) || categoriesObj is not Dictionary<string, object> categoriesDict)
        {
            return;
        }

        foreach (var categoryEntry in categoriesDict)
        {
            if (categoryEntry.Value is not List<object> list)
            {
                continue;
            }

            foreach (var item in list)
            {
                if (item is not Dictionary<string, object> entryDict)
                {
                    continue;
                }

                var entryLabel = entryDict.TryGetValue("label", out var labelObj) ? labelObj as string : null;
                var entryPath = entryDict.TryGetValue("path", out var pathObj) ? pathObj as string : null;
                if (string.IsNullOrWhiteSpace(entryLabel) || string.IsNullOrWhiteSpace(entryPath))
                {
                    continue;
                }

                var key = $"{categoryEntry.Key}|{entryLabel}";
                manifestSpriteLookup[key] = entryPath;
            }
        }
    }

    private Sprite LoadSpriteAtPath(string assetPath)
    {
        if (string.IsNullOrWhiteSpace(assetPath))
        {
            return null;
        }

#if UNITY_EDITOR
        var assetSprite = AssetDatabase.LoadAssetAtPath<Sprite>(assetPath);
        if (assetSprite != null)
        {
            return assetSprite;
        }
#endif

        if (assetPath.Contains("/Resources/", StringComparison.OrdinalIgnoreCase))
        {
            var resourcesIndex = assetPath.IndexOf("/Resources/", StringComparison.OrdinalIgnoreCase);
            var resourcesPath = assetPath.Substring(resourcesIndex + "/Resources/".Length);
            resourcesPath = Path.ChangeExtension(resourcesPath, null);
            var resourceSprite = Resources.Load<Sprite>(resourcesPath);
            if (resourceSprite != null)
            {
                return resourceSprite;
            }
        }

        if (assetPath.StartsWith("Assets/", StringComparison.OrdinalIgnoreCase))
        {
            var relative = assetPath.Substring("Assets/".Length);
            var fullPath = Path.Combine(Application.dataPath, relative);
            if (File.Exists(fullPath))
            {
                var bytes = File.ReadAllBytes(fullPath);
                var texture = new Texture2D(2, 2, TextureFormat.RGBA32, false);
                if (texture.LoadImage(bytes))
                {
                    return Sprite.Create(texture, new Rect(0f, 0f, texture.width, texture.height), new Vector2(0.5f, 0.5f), 100f);
                }
            }
        }

        return null;
    }

    private bool TryParseHexColor(string hex, out Color color)
    {
        color = Color.white;
        if (string.IsNullOrWhiteSpace(hex))
        {
            return false;
        }

        if (!hex.StartsWith("#"))
        {
            hex = $"#{hex}";
        }

        return ColorUtility.TryParseHtmlString(hex, out color);
    }
}
