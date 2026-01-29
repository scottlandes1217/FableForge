using System;
using System.Collections.Generic;
using FableForge.Models;
using UnityEngine;

[Serializable]
public class CharacterPreset
{
    public string rig;
    public Dictionary<string, string> slots = new Dictionary<string, string>();
    public Dictionary<string, string> tints = new Dictionary<string, string>();

    public static CharacterPreset FromSelections(
        string rigId,
        IReadOnlyList<AppearanceSelection> selections,
        IReadOnlyList<AppearanceCategoryDefinition> definitions)
    {
        var preset = new CharacterPreset
        {
            rig = string.IsNullOrWhiteSpace(rigId) ? "humanoid_v1" : rigId
        };

        if (definitions != null)
        {
            foreach (var definition in definitions)
            {
                if (definition == null || string.IsNullOrWhiteSpace(definition.label))
                {
                    continue;
                }

                var selection = selections != null
                    ? FindSelection(selections, definition.category)
                    : default;
                var option = !string.IsNullOrWhiteSpace(selection.optionId)
                    ? definition.options.Find(item => item.id == selection.optionId)
                    : (definition.options.Count > 0 ? definition.options[0] : null);

                if (option == null)
                {
                    continue;
                }

                if (!string.IsNullOrWhiteSpace(option.slotCategory) && !string.IsNullOrWhiteSpace(option.slotLabel))
                {
                    preset.slots[option.slotCategory] = option.slotLabel;
                }

                if (!string.IsNullOrWhiteSpace(option.slotCategorySecondary) && !string.IsNullOrWhiteSpace(option.slotLabelSecondary))
                {
                    preset.slots[option.slotCategorySecondary] = option.slotLabelSecondary;
                }

                if (!string.IsNullOrWhiteSpace(option.tintKey) && !string.IsNullOrWhiteSpace(option.tintHex))
                {
                    preset.tints[option.tintKey] = option.tintHex;
                }
            }
        }

        if (!preset.slots.ContainsKey("Body"))
        {
            preset.slots["Body"] = "placeholder";
        }

        if (!preset.slots.ContainsKey("Head"))
        {
            preset.slots["Head"] = "placeholder";
        }

        return preset;
    }

    public static CharacterPreset FromJson(string json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return null;
        }

        var parsed = MiniJson.Deserialize(json) as Dictionary<string, object>;
        if (parsed == null)
        {
            return null;
        }

        var preset = new CharacterPreset();
        if (parsed.TryGetValue("rig", out var rigValue))
        {
            preset.rig = rigValue as string;
        }

        if (parsed.TryGetValue("slots", out var slotsValue) && slotsValue is Dictionary<string, object> slotsDict)
        {
            foreach (var entry in slotsDict)
            {
                preset.slots[entry.Key] = entry.Value as string;
            }
        }

        if (parsed.TryGetValue("tints", out var tintsValue) && tintsValue is Dictionary<string, object> tintsDict)
        {
            foreach (var entry in tintsDict)
            {
                preset.tints[entry.Key] = entry.Value as string;
            }
        }

        return preset;
    }

    public string ToJson()
    {
        var slotsPayload = new Dictionary<string, object>();
        foreach (var entry in slots)
        {
            slotsPayload[entry.Key] = entry.Value;
        }

        var tintsPayload = new Dictionary<string, object>();
        foreach (var entry in tints)
        {
            tintsPayload[entry.Key] = entry.Value;
        }

        var payload = new Dictionary<string, object>
        {
            { "rig", rig },
            { "slots", slotsPayload },
            { "tints", tintsPayload }
        };

        return MiniJson.Serialize(payload);
    }

    private static AppearanceSelection FindSelection(IReadOnlyList<AppearanceSelection> selections, AppearanceCategory category)
    {
        for (var i = 0; i < selections.Count; i++)
        {
            if (selections[i].category == category)
            {
                return selections[i];
            }
        }

        return default;
    }
}
