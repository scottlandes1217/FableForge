using FableForge.Systems;
using UnityEngine;

public class CompanionInstance : MonoBehaviour
{
    public CompanionDefinitionData Definition { get; private set; }

    public string CompanionId => Definition?.id ?? string.Empty;
    public string DisplayName => !string.IsNullOrWhiteSpace(Definition?.name) ? Definition.name : CompanionId;
    public string RequiredBefriendingItem => Definition?.requiredBefriendingItem ?? string.Empty;

    public void Initialize(CompanionDefinitionData definition)
    {
        Definition = definition;
    }
}
