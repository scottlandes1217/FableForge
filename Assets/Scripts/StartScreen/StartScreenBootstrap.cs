using UnityEngine;

public static class StartScreenBootstrap
{
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void EnsureStartScreen()
    {
        if (Object.FindFirstObjectByType<StartScreenController>() != null)
        {
            return;
        }

        var characterCreation = Object.FindFirstObjectByType<CharacterCreationBootstrap>();
        if (characterCreation != null)
        {
            characterCreation.Deactivate();
        }

        var controllerObject = new GameObject("StartScreenController");
        controllerObject.AddComponent<StartScreenController>();
    }
}
