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
    [SerializeField] private string sideSuffix = "side";
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
        if (baseLabels == null || baseLabels.Count == 0)
        {
            return;
        }

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

            if (!baseLabels.TryGetValue(category, out var baseLabel) || string.IsNullOrWhiteSpace(baseLabel))
            {
                continue;
            }

            var targetLabel = baseLabel;
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

            resolver.SetCategoryAndLabel(category, targetLabel);
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

        return $"{baseLabel}_{suffix}";
    }
}
