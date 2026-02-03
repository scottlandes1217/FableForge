using System.Collections.Generic;
using UnityEngine;
using UnityEngine.U2D.Animation;

public enum FacingDirection
{
    Front,
    Side,
    Back
}

public class FacingDirectionResolver : MonoBehaviour
{
    [SerializeField] private FacingDirection facing = FacingDirection.Front;
    [SerializeField] private string frontSuffix = "front";
    [SerializeField] private string sideSuffix = "right";
    [SerializeField] private string backSuffix = "back";

    private SpriteLibrary spriteLibrary;

    public FacingDirection CurrentFacing => facing;

    public void SetFacing(FacingDirection direction, Dictionary<string, string> baseLabels = null)
    {
        facing = direction;
        ApplyFacing(baseLabels);
    }

    public void ApplyFacing(Dictionary<string, string> baseLabels)
    {
        if (baseLabels != null && baseLabels.Count > 0)
        {
            if (spriteLibrary == null)
            {
                spriteLibrary = GetComponentInParent<SpriteLibrary>();
            }

            var suffix = GetSuffix();
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
                    continue;
                }

                // Hair is set by manifest + visibility only; do not overwrite from library.
                if (string.Equals(category, "HairFront", System.StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(category, "HairBack", System.StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(category, "HairSide", System.StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                if (!baseLabels.TryGetValue(category, out var baseLabel) || string.IsNullOrWhiteSpace(baseLabel))
                {
                    continue;
                }

                var targetLabel = baseLabel;
                // Face slots use same naming as body: direction in name (e.g. eyes_side_round_01, not eyes_round_01_right)
                var isFaceCategory = string.Equals(category, "Eyes", System.StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(category, "Eyebrows", System.StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(category, "Mouth", System.StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(category, "Nose", System.StringComparison.OrdinalIgnoreCase);
                if (isFaceCategory && facing == FacingDirection.Side)
                {
                    var idx = baseLabel.IndexOf('_');
                    var sideLabel = idx > 0 ? baseLabel.Substring(0, idx) + "_side_" + baseLabel.Substring(idx + 1) : baseLabel + "_side";
                    if (spriteLibrary != null && spriteLibrary.spriteLibraryAsset != null && spriteLibrary.spriteLibraryAsset.GetSprite(category, sideLabel) != null)
                        targetLabel = sideLabel;
                    else
                        targetLabel = sideLabel; // use anyway so manifest path can resolve
                }
                else
                {
                    var candidate = BuildDirectionCandidate(baseLabel, suffix);
                    if (spriteLibrary != null && spriteLibrary.spriteLibraryAsset != null)
                    {
                        var sprite = spriteLibrary.spriteLibraryAsset.GetSprite(category, candidate);
                        if (sprite != null)
                        {
                            targetLabel = candidate;
                        }
                        else
                        {
                            var appended = $"{baseLabel}_{suffix}";
                            sprite = spriteLibrary.spriteLibraryAsset.GetSprite(category, appended);
                            if (sprite != null)
                            {
                                targetLabel = appended;
                            }
                        }
                    }
                }

                resolver.SetCategoryAndLabel(category, targetLabel);
            }
        }

        ApplyHairSlotVisibility();
    }

    /// <summary>
    /// One hair slot per facing: Front (south) = HairFront, Back (north) = HairBack, Side (east/west) = HairSide (flip for west).
    /// Face slots (Eyes, Eyebrows, Mouth, Nose) only show when facing Front or Side; hidden when facing Back (north).
    /// Call this after hair/face sprites are set so nothing overwrites visibility.
    /// </summary>
    public void ApplyHairVisibilityOnly()
    {
        var slotsRoot = transform.Find("Slots");
        if (slotsRoot == null)
        {
            return;
        }

        var hairFront = slotsRoot.Find("HairFront");
        var hairBack = slotsRoot.Find("HairBack");
        var hairSide = slotsRoot.Find("HairSide");

        SetSlotRendererEnabled(hairFront, facing == FacingDirection.Front);
        SetSlotRendererEnabled(hairBack, facing == FacingDirection.Back);
        SetSlotRendererEnabled(hairSide, facing == FacingDirection.Side);

        // Face only visible when camera can see it (Front or Side); hide when facing away (Back/north)
        var showFace = facing == FacingDirection.Front || facing == FacingDirection.Side;
        SetSlotRendererEnabled(slotsRoot.Find("Eyes"), showFace);
        SetSlotRendererEnabled(slotsRoot.Find("Eyebrows"), showFace);
        SetSlotRendererEnabled(slotsRoot.Find("Mouth"), showFace);
        SetSlotRendererEnabled(slotsRoot.Find("Nose"), showFace);
    }

    /// <summary>Alias so ApplyHairVisibilityOnly can stay as the public name.</summary>
    private void ApplyHairSlotVisibility() => ApplyHairVisibilityOnly();

    private static void SetSlotRendererEnabled(Transform slot, bool enabled)
    {
        if (slot == null)
        {
            return;
        }

        var r = slot.GetComponent<SpriteRenderer>();
        if (r != null)
        {
            r.enabled = enabled;
        }
    }

    private string GetSuffix()
    {
        switch (facing)
        {
            case FacingDirection.Back:
                return backSuffix;
            case FacingDirection.Side:
                return sideSuffix;
            default:
                return frontSuffix;
        }
    }

    private string BuildDirectionCandidate(string baseLabel, string suffix)
    {
        if (string.IsNullOrWhiteSpace(baseLabel))
        {
            return baseLabel;
        }

        if (baseLabel.Contains("_front_"))
        {
            return baseLabel.Replace("_front_", $"_{suffix}_");
        }
        if (baseLabel.Contains("_side_"))
        {
            return baseLabel.Replace("_side_", $"_{suffix}_");
        }
        if (baseLabel.Contains("_back_"))
        {
            return baseLabel.Replace("_back_", $"_{suffix}_");
        }
        if (baseLabel.Contains("_right_"))
        {
            return baseLabel.Replace("_right_", $"_{suffix}_");
        }

        return $"{baseLabel}_{suffix}";
    }
}
