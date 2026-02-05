using System.Collections.Generic;
using UnityEngine;
using UnityEngine.U2D.Animation;

/// <summary>
/// Cycles Body, Top, and Bottom through walk frames (_walk_01, _walk_02, ...) when the character is moving.
/// When idle, shows the normal idle sprites (_01).
/// Add walk-frame sprites to the same Parts folders with names like body_human_male_front_walk_01.png.
/// </summary>
public class CharacterWalkAnimator : MonoBehaviour
{
    [Tooltip("Number of walk frames per direction (e.g. 4 = _walk_01 through _walk_04).")]
    [SerializeField] private int walkFrameCount = 4;

    [Tooltip("Frames per second when walking.")]
    [SerializeField] private float walkFps = 8f;

    [Tooltip("Slot categories that have walk variants (Body, Top, Bottom).")]
    [SerializeField] private string[] animatedSlots = { "Body", "Top", "Bottom" };

    private FacingDirectionResolver facingResolver;
    private CharacterCustomizer customizer;
    private PlayerMovementController movement;
    private float walkTime;

    private void Awake()
    {
        facingResolver = GetComponent<FacingDirectionResolver>();
        if (facingResolver == null)
        {
            facingResolver = gameObject.AddComponent<FacingDirectionResolver>();
        }

        customizer = GetComponent<CharacterCustomizer>();
        movement = GetComponent<PlayerMovementController>();
    }

    private void LateUpdate()
    {
        if (customizer == null || customizer.ActivePresetSlots == null || facingResolver == null)
        {
            return;
        }

        var slots = customizer.GetSlotsForFacing();
        var currentFacing = facingResolver.CurrentFacing;
        var resolvedSlots = customizer.BuildResolvedSlotsForFacing(slots, currentFacing);
        var isMoving = movement != null && movement.LastMovementInputSqrMagnitude > 0.01f;

        if (isMoving)
        {
            walkTime += Time.deltaTime;
            var frameIndex = Mathf.FloorToInt(walkTime * walkFps) % Mathf.Max(1, walkFrameCount);
            var frameLabel = (frameIndex + 1).ToString("00");
            resolvedSlots = BuildWalkLabels(resolvedSlots, frameLabel);
        }
        else
        {
            walkTime = 0f;
        }

        facingResolver.SetFacing(currentFacing, resolvedSlots);
        customizer.ApplyResolvedSlotsFromManifest(resolvedSlots);
        facingResolver.ApplyHairVisibilityOnly();
        customizer.RefreshEquipmentSprites();
        var flipX = false;
        var firstRenderer = customizer.GetComponentInChildren<SpriteRenderer>(true);
        if (firstRenderer != null) flipX = firstRenderer.flipX;
        customizer.ApplyEquipmentSlotTransforms(currentFacing, flipX);
    }

    private Dictionary<string, string> BuildWalkLabels(Dictionary<string, string> resolvedSlots, string frameLabel)
    {
        var result = new Dictionary<string, string>(resolvedSlots);
        if (animatedSlots == null)
        {
            return result;
        }

        foreach (var slot in animatedSlots)
        {
            if (string.IsNullOrWhiteSpace(slot) || !resolvedSlots.TryGetValue(slot, out var idleLabel))
            {
                continue;
            }

            var walkLabel = idleLabel.Replace("_01", "_walk_" + frameLabel);
            result[slot] = walkLabel;
        }

        return result;
    }
}
