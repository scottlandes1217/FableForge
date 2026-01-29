using FableForge.Systems;
using UnityEngine;

public class EnemyInstance : MonoBehaviour
{
    public EnemyDefinitionData Definition { get; private set; }
    public bool InBattle { get; set; }

    public string EnemyId => Definition?.id ?? string.Empty;
    public string DisplayName => !string.IsNullOrWhiteSpace(Definition?.name) ? Definition.name : EnemyId;

    public void Initialize(EnemyDefinitionData definition)
    {
        Definition = definition;
        InBattle = false;
    }
}
