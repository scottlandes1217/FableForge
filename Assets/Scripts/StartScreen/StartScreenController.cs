using System;
using System.Collections;
using System.Collections.Generic;
using TMPro;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem.UI;
#endif

public class StartScreenController : MonoBehaviour
{
    private static StartScreenController activeInstance;
    private enum ScreenState
    {
        Logo,
        Menu,
        CharacterSelection,
        SaveSlotSelection,
        DeleteConfirm
    }

    private const int MaxSaveSlotsPerCharacter = 5;
    private const string CharacterKeyPrefix = "FableForge_Character_";
    private const string SaveSlotKeyPrefix = "FableForge_SaveSlot_";

    private Canvas canvas;
    private RectTransform panelRoot;
    private RectTransform contentRoot;
    private VerticalLayoutGroup panelLayout;
    private ScreenState currentState = ScreenState.Logo;
    private int selectedSlot = -1;
    private int deleteCandidateSlot = -1;
    private TextMeshProUGUI tapPrompt;
    private Coroutine tapFlashRoutine;

    private readonly Color buttonDisabledColor = new Color(0.75f, 0.75f, 0.75f, 1f);

    private void Awake()
    {
        if (activeInstance != null && activeInstance != this)
        {
            Destroy(gameObject);
            return;
        }

        activeInstance = this;
    }

    public static StartScreenController GetOrCreate()
    {
        if (activeInstance != null)
        {
            return activeInstance;
        }

        var existing = FindFirstObjectByType<StartScreenController>();
        if (existing != null)
        {
            activeInstance = existing;
            return existing;
        }

        var allStartScreens = Resources.FindObjectsOfTypeAll<StartScreenController>();
        if (allStartScreens != null && allStartScreens.Length > 0)
        {
            activeInstance = allStartScreens[0];
            return allStartScreens[0];
        }

        var startScreenObject = new GameObject("StartScreenController");
        activeInstance = startScreenObject.AddComponent<StartScreenController>();
        return activeInstance;
    }

    private void OnDestroy()
    {
        if (activeInstance == this)
        {
            activeInstance = null;
        }

        ClearPanel();
    }

    private void Start()
    {
        canvas = EnsureCanvas();
        EnsureEventSystem();
        MigrateLegacySlots();
        BuildScreen();
    }

    public void Activate()
    {
        enabled = true;
        canvas = EnsureCanvas();
        EnsureEventSystem();
        if (canvas != null)
        {
            canvas.enabled = true;
        }
        if (panelRoot != null)
        {
            panelRoot.gameObject.SetActive(true);
        }
        MigrateLegacySlots();
        BuildScreen();
    }

    public void ShowMainMenu()
    {
        currentState = ScreenState.Menu;
        BuildScreen();
    }

    private void BuildScreen()
    {
        ClearPanel();
        panelRoot = CreatePanel(canvas.transform);

        switch (currentState)
        {
            case ScreenState.Logo:
                BuildLogoScreen();
                break;
            case ScreenState.Menu:
                BuildMenuScreen();
                break;
            case ScreenState.CharacterSelection:
                BuildCharacterSelection();
                break;
            case ScreenState.SaveSlotSelection:
                BuildSaveSlotSelection();
                break;
            case ScreenState.DeleteConfirm:
                BuildDeleteConfirm();
                break;
        }
    }

    private void BuildLogoScreen()
    {
        SetBackgroundSprite("Main/book_cover");
        SetLayoutAlignment(TextAnchor.LowerCenter);
        SetContentOffsetY(0f);
        CreateSpacer(panelRoot, 12f);
        CreateBottomPrompt("Tap to Continue");
        CreateFullScreenTapTarget();
    }

    private void CreateFullScreenTapTarget()
    {
        var tapObject = new GameObject("TapAnywhereTarget");
        tapObject.transform.SetParent(canvas.transform, false);
        var rect = tapObject.AddComponent<RectTransform>();
        rect.anchorMin = Vector2.zero;
        rect.anchorMax = Vector2.one;
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;

        var image = tapObject.AddComponent<Image>();
        image.color = new Color(1f, 1f, 1f, 0f);
        image.raycastTarget = true;

        var button = tapObject.AddComponent<Button>();
        button.onClick.AddListener(() =>
        {
            Destroy(tapObject);
            StopTapFlash();
            currentState = ScreenState.Menu;
            BuildScreen();
        });
    }

    private void SetBackgroundSprite(string resourcePath)
    {
        if (panelRoot == null)
        {
            return;
        }

        var background = panelRoot.parent != null ? panelRoot.parent.Find("Background") : null;
        if (background == null)
        {
            background = panelRoot.Find("Background");
        }

        if (background == null)
        {
            return;
        }

        var image = background.GetComponent<Image>();
        if (image == null)
        {
            return;
        }

        var sprite = Resources.Load<Sprite>(resourcePath);
        if (sprite != null)
        {
            image.sprite = sprite;
            image.type = Image.Type.Simple;
            var useCoverAspect = resourcePath == "Main/book_cover";
            image.preserveAspect = useCoverAspect;

            var aspectFitter = image.GetComponent<AspectRatioFitter>();
            if (useCoverAspect)
            {
                if (aspectFitter == null)
                {
                    aspectFitter = image.gameObject.AddComponent<AspectRatioFitter>();
                }

                aspectFitter.aspectMode = AspectRatioFitter.AspectMode.EnvelopeParent;
                aspectFitter.aspectRatio = sprite.rect.width / sprite.rect.height;
            }
            else if (aspectFitter != null)
            {
                Destroy(aspectFitter);
            }
        }
    }

    private void CreateBottomPrompt(string text)
    {
        var promptObject = new GameObject("BottomPrompt");
        promptObject.transform.SetParent(canvas.transform, false);
        var rect = promptObject.AddComponent<RectTransform>();
        rect.anchorMin = new Vector2(0.5f, 0f);
        rect.anchorMax = new Vector2(0.5f, 0f);
        rect.pivot = new Vector2(0.5f, 0f);
        rect.anchoredPosition = new Vector2(0f, 24f);
        rect.sizeDelta = new Vector2(500f, 48f);

        tapPrompt = promptObject.AddComponent<TextMeshProUGUI>();
        tapPrompt.text = text;
        tapPrompt.fontSize = 32f;
        tapPrompt.alignment = TextAlignmentOptions.Center;
        tapPrompt.color = Color.white;

        StartTapFlash();
    }

    private void StartTapFlash()
    {
        StopTapFlash();
        if (tapPrompt == null)
        {
            return;
        }

        tapFlashRoutine = StartCoroutine(FlashPrompt());
    }

    private void StopTapFlash()
    {
        if (tapFlashRoutine != null)
        {
            StopCoroutine(tapFlashRoutine);
            tapFlashRoutine = null;
        }
    }

    private IEnumerator FlashPrompt()
    {
        var speed = 1.2f;
        while (true)
        {
            if (tapPrompt != null)
            {
                var alpha = 0.35f + 0.65f * (0.5f + 0.5f * Mathf.Sin(Time.unscaledTime * speed * Mathf.PI * 2f));
                var color = tapPrompt.color;
                color.a = alpha;
                tapPrompt.color = color;
            }

            yield return null;
        }
    }

    private void BuildMenuScreen()
    {
        SetBackgroundSprite("Main/book_page");
        SetLayoutAlignment(TextAnchor.MiddleCenter);
        ConfigureMenuLayout();
        SetContentTop(0.96f);
        SetContentOffsetY(200f);
        CreateHeaderContainer(panelRoot, "Main Menu");
        CreateSpacer(panelRoot, 12f);

        var hasSave = AnyCharactersExist();

        if (hasSave)
        {
            CreateButton(panelRoot, "Continue", () =>
            {
                currentState = ScreenState.CharacterSelection;
                BuildScreen();
            }, 250f, true, null, 50f);
        }

        var characterCount = CharacterIndexRegistry.Count;
        if (characterCount < 5)
        {
            CreateButton(panelRoot, "Start New Game", () =>
            {
                SaveSelectedCharacter(GetNextAvailableCharacter());
                SaveSelectedSaveSlot(0);
                LaunchCharacterCreation();
            }, 250f, true, null, 50f);
        }
    }

    private void BuildCharacterSelection()
    {
        SetBackgroundSprite("Main/book_page");
        SetLayoutAlignment(TextAnchor.UpperCenter);
        CreateHeader(panelRoot, "Characters", 68f, 72f);
        CreateText(panelRoot, "Select a character to view its saves or delete one.");
        CreateSpacer(panelRoot, 12f);

        var hasCharacters = false;
        var characterIndices = CharacterIndexRegistry.GetIndices();
        for (var i = 0; i < characterIndices.Count; i++)
        {
            var characterIndex = characterIndices[i];
            if (!CharacterHasData(characterIndex))
            {
                continue;
            }

            hasCharacters = true;
            var characterLabel = GetCharacterDisplayName(characterIndex);
            var row = CreateHorizontalGroup(panelRoot, 12f, 120f);
            CreateButton(row, characterLabel, () =>
            {
                selectedSlot = characterIndex;
                currentState = ScreenState.SaveSlotSelection;
                BuildScreen();
            }, 460f, true, null, 120f);

            CreateDeleteButton(row, "Delete", () =>
            {
                deleteCandidateSlot = characterIndex;
                currentState = ScreenState.DeleteConfirm;
                BuildScreen();
            }, 96f, 96f);
        }

        if (!hasCharacters)
        {
            CreateText(panelRoot, "No saved characters yet.");
            CreateSpacer(panelRoot, 8f);
        }

        CreateFlexibleSpacer(panelRoot);
        var backRow = CreateHorizontalGroup(panelRoot, 0f, 44f);
        var backRowLayout = backRow.GetComponent<HorizontalLayoutGroup>();
        if (backRowLayout != null)
        {
            backRowLayout.childAlignment = TextAnchor.MiddleLeft;
        }
        CreateBackButton(backRow, "Back", () =>
        {
            currentState = ScreenState.Menu;
            BuildScreen();
        }, 110f, 44f);
    }

    private void BuildSaveSlotSelection()
    {
        SetBackgroundSprite("Main/book_page");
        SetLayoutAlignment(TextAnchor.UpperCenter);
        CreateHeader(panelRoot, "Character Saves", 68f, 72f);
        CreateText(panelRoot, "Choose a save slot to continue.");
        CreateSpacer(panelRoot, 12f);

        var hasAnySaves = false;
        for (var i = 0; i < MaxSaveSlotsPerCharacter; i++)
        {
            var saveSlotIndex = i;
            if (!SaveSlotHasData(selectedSlot, saveSlotIndex))
            {
                continue;
            }

            hasAnySaves = true;
            var globalSlotIndex = GetGlobalSlotIndex(selectedSlot, saveSlotIndex);
            var slotLabel = GetSaveSlotDisplayName(selectedSlot, saveSlotIndex);
            var row = CreateHorizontalGroup(panelRoot, 12f, 120f);
            CreateButton(row, slotLabel, () =>
            {
                GameFlow.ContinueGame(globalSlotIndex);
            }, 460f, true, null, 120f);

            CreateDeleteButton(row, "Delete", () =>
            {
                DeleteSaveSlot(selectedSlot, saveSlotIndex);
                BuildScreen();
            }, 96f, 96f);
        }

        if (!hasAnySaves)
        {
            CreateText(panelRoot, "No saved games for this character.");
            CreateSpacer(panelRoot, 8f);
        }

        CreateFlexibleSpacer(panelRoot);
        var backRow = CreateHorizontalGroup(panelRoot, 0f, 44f);
        var backRowLayout = backRow.GetComponent<HorizontalLayoutGroup>();
        if (backRowLayout != null)
        {
            backRowLayout.childAlignment = TextAnchor.MiddleLeft;
        }
        CreateBackButton(backRow, "Back", () =>
        {
            currentState = ScreenState.CharacterSelection;
            BuildScreen();
        }, 110f, 44f);
    }

    private void BuildDeleteConfirm()
    {
        SetBackgroundSprite("Main/book_page");
        SetLayoutAlignment(TextAnchor.MiddleCenter);
        CreateHeader(panelRoot, "Delete Character");
        CreateText(panelRoot, $"Delete {GetCharacterDisplayName(deleteCandidateSlot)}? This cannot be undone.");
        CreateSpacer(panelRoot, 12f);

        CreateButton(panelRoot, "Cancel", () =>
        {
            currentState = ScreenState.CharacterSelection;
            BuildScreen();
        }, 160f, true);

        CreateDeleteButton(panelRoot, "Delete", () =>
        {
            DeleteCharacter(deleteCandidateSlot);
            deleteCandidateSlot = -1;
            currentState = ScreenState.CharacterSelection;
            BuildScreen();
        }, 160f, 44f);
    }

    private void LaunchCharacterCreation()
    {
        ClearPanel();
        var worldPreview = GameObject.Find("WorldPreview");
        if (worldPreview != null)
        {
            Destroy(worldPreview);
        }

        var gameScene = FindFirstObjectByType<GameSceneController>();
        if (gameScene != null)
        {
            Destroy(gameScene.gameObject);
        }

        var gameCamera = GameObject.Find("GameCamera");
        if (gameCamera != null)
        {
            Destroy(gameCamera);
        }

        var bootstrap = FindFirstObjectByType<CharacterCreationBootstrap>();
        if (bootstrap == null)
        {
            var bootstrapObject = new GameObject("CharacterCreationBootstrap");
            bootstrap = bootstrapObject.AddComponent<CharacterCreationBootstrap>();
        }

        bootstrap.Activate();
    }

    private bool AnyCharactersExist()
    {
        return CharacterIndexRegistry.Count > 0;
    }

    private bool CharacterHasData(int characterIndex)
    {
        return PlayerPrefs.HasKey($"{CharacterKeyPrefix}{characterIndex}_Name");
    }

    private string GetSaveSlotDisplayName(int characterIndex, int saveSlotIndex)
    {
        if (!SaveSlotHasData(characterIndex, saveSlotIndex))
        {
            return $"Save {saveSlotIndex + 1} - Empty";
        }

        var globalSlotIndex = GetGlobalSlotIndex(characterIndex, saveSlotIndex);
        var timestamp = PlayerPrefs.GetString($"{SaveSlotKeyPrefix}{globalSlotIndex}_LastPlayed", string.Empty);
        if (DateTime.TryParse(timestamp, out var parsed))
        {
            return $"Save {saveSlotIndex + 1} - {parsed:g}";
        }

        return $"Save {saveSlotIndex + 1}";
    }

    private string GetCharacterDisplayName(int slotIndex)
    {
        if (!CharacterHasData(slotIndex))
        {
            return "Unknown";
        }

        var name = PlayerPrefs.GetString($"{CharacterKeyPrefix}{slotIndex}_Name", "Unknown");
        var characterClass = PlayerPrefs.GetString($"{CharacterKeyPrefix}{slotIndex}_Class", string.Empty);
        if (string.IsNullOrWhiteSpace(characterClass))
        {
            return name;
        }

        return $"{name} ({characterClass})";
    }

    private int GetNextAvailableCharacter()
    {
        return CharacterIndexRegistry.GetNextAvailableIndex();
    }

    private void DeleteCharacter(int characterIndex)
    {
        PlayerPrefs.DeleteKey($"{CharacterKeyPrefix}{characterIndex}_Name");
        PlayerPrefs.DeleteKey($"{CharacterKeyPrefix}{characterIndex}_Class");

        for (var i = 0; i < MaxSaveSlotsPerCharacter; i++)
        {
            var globalSlotIndex = GetGlobalSlotIndex(characterIndex, i);
            PlayerPrefs.DeleteKey($"{SaveSlotKeyPrefix}{globalSlotIndex}_LastPlayed");

            var savePath = FableForge.Systems.SaveManager.GetSlotPath(globalSlotIndex);
            if (System.IO.File.Exists(savePath))
            {
                System.IO.File.Delete(savePath);
            }
        }

        CharacterIndexRegistry.Remove(characterIndex);
        PlayerPrefs.Save();
    }

    private void DeleteSaveSlot(int characterIndex, int saveSlotIndex)
    {
        var globalSlotIndex = GetGlobalSlotIndex(characterIndex, saveSlotIndex);
        PlayerPrefs.DeleteKey($"{SaveSlotKeyPrefix}{globalSlotIndex}_LastPlayed");
        PlayerPrefs.Save();

        var savePath = FableForge.Systems.SaveManager.GetSlotPath(globalSlotIndex);
        if (System.IO.File.Exists(savePath))
        {
            System.IO.File.Delete(savePath);
        }
    }

    private bool SaveSlotHasData(int characterIndex, int saveSlotIndex)
    {
        if (characterIndex < 0 || saveSlotIndex < 0)
        {
            return false;
        }

        var globalSlotIndex = GetGlobalSlotIndex(characterIndex, saveSlotIndex);
        var savePath = FableForge.Systems.SaveManager.GetSlotPath(globalSlotIndex);
        return System.IO.File.Exists(savePath);
    }

    private int GetGlobalSlotIndex(int characterIndex, int saveSlotIndex)
    {
        return characterIndex * MaxSaveSlotsPerCharacter + saveSlotIndex;
    }

    private void SaveSelectedCharacter(int characterIndex)
    {
        PlayerPrefs.SetInt("FableForge_SelectedCharacter", characterIndex);
        PlayerPrefs.Save();
    }

    private void SaveSelectedSaveSlot(int saveSlotIndex)
    {
        PlayerPrefs.SetInt("FableForge_SelectedSaveSlot", saveSlotIndex);
        PlayerPrefs.Save();
    }

    private void MigrateLegacySlots()
    {
        var legacySlots = 3;
        for (var i = 0; i < legacySlots; i++)
        {
            var legacyNameKey = $"{SaveSlotKeyPrefix}{i}_CharacterName";
            if (!PlayerPrefs.HasKey(legacyNameKey))
            {
                continue;
            }

            var name = PlayerPrefs.GetString(legacyNameKey, string.Empty);
            var legacyClassKey = $"{SaveSlotKeyPrefix}{i}_Class";
            var characterClass = PlayerPrefs.GetString(legacyClassKey, string.Empty);

            var newNameKey = $"{CharacterKeyPrefix}{i}_Name";
            if (!PlayerPrefs.HasKey(newNameKey))
            {
                PlayerPrefs.SetString(newNameKey, name);
                PlayerPrefs.SetString($"{CharacterKeyPrefix}{i}_Class", characterClass);
            }

            CharacterIndexRegistry.Register(i);

            var legacyLastPlayedKey = $"{SaveSlotKeyPrefix}{i}_LastPlayed";
            var lastPlayed = PlayerPrefs.GetString(legacyLastPlayedKey, string.Empty);
            var newGlobalSlotIndex = GetGlobalSlotIndex(i, 0);
            if (!string.IsNullOrWhiteSpace(lastPlayed))
            {
                PlayerPrefs.SetString($"{SaveSlotKeyPrefix}{newGlobalSlotIndex}_LastPlayed", lastPlayed);
            }

            var legacyPath = FableForge.Systems.SaveManager.GetSlotPath(i);
            var newPath = FableForge.Systems.SaveManager.GetSlotPath(newGlobalSlotIndex);
            if (System.IO.File.Exists(legacyPath) && !System.IO.File.Exists(newPath))
            {
                System.IO.File.Move(legacyPath, newPath);
            }

            PlayerPrefs.DeleteKey(legacyNameKey);
            PlayerPrefs.DeleteKey(legacyClassKey);
            PlayerPrefs.DeleteKey(legacyLastPlayedKey);
        }

        PlayerPrefs.Save();
    }

    private Canvas EnsureCanvas()
    {
        var existingCanvas = FindStartScreenCanvas();
        if (existingCanvas != null)
        {
            ConfigureCanvasScaler(existingCanvas);
            existingCanvas.enabled = true;
            existingCanvas.gameObject.SetActive(true);
            if (existingCanvas.GetComponent<GraphicRaycaster>() == null)
            {
                existingCanvas.gameObject.AddComponent<GraphicRaycaster>();
            }
            return existingCanvas;
        }

        var canvasObject = new GameObject("MainCanvas");
        var createdCanvas = canvasObject.AddComponent<Canvas>();
        createdCanvas.renderMode = RenderMode.ScreenSpaceOverlay;
        ConfigureCanvasScaler(createdCanvas);
        canvasObject.AddComponent<GraphicRaycaster>();
        return createdCanvas;
    }

    private Canvas FindStartScreenCanvas()
    {
        var activeCanvas = FindFirstObjectByType<Canvas>();
        if (IsStartScreenCanvas(activeCanvas))
        {
            return activeCanvas;
        }

        var canvases = Resources.FindObjectsOfTypeAll<Canvas>();
        foreach (var canvas in canvases)
        {
            if (IsStartScreenCanvas(canvas))
            {
                return canvas;
            }
        }

        return null;
    }

    private bool IsStartScreenCanvas(Canvas canvas)
    {
        if (canvas == null)
        {
            return false;
        }

        if (canvas.name == "MainCanvas")
        {
            return true;
        }

        return canvas.transform.Find("StartScreenPanel") != null;
    }

    private void EnsureEventSystem()
    {
        if (FindFirstObjectByType<EventSystem>() != null)
        {
            return;
        }

        var eventSystem = new GameObject("EventSystem");
        eventSystem.AddComponent<EventSystem>();
#if ENABLE_INPUT_SYSTEM
        eventSystem.AddComponent<InputSystemUIInputModule>();
#else
        eventSystem.AddComponent<StandaloneInputModule>();
#endif
    }

    private void ClearPanel()
    {
        if (panelRoot != null)
        {
            var panelObject = panelRoot.parent != null ? panelRoot.parent.gameObject : panelRoot.gameObject;
            Destroy(panelObject);
            panelRoot = null;
        }

        var tapTarget = GameObject.Find("TapAnywhereTarget");
        if (tapTarget != null)
        {
            Destroy(tapTarget);
        }

        var prompt = GameObject.Find("BottomPrompt");
        if (prompt != null)
        {
            Destroy(prompt);
        }

        var panel = GameObject.Find("StartScreenPanel");
        if (panel != null)
        {
            Destroy(panel);
        }
    }

    private RectTransform CreatePanel(Transform parent)
    {
        var panelObject = new GameObject("StartScreenPanel");
        panelObject.transform.SetParent(parent, false);
        var panelRect = panelObject.AddComponent<RectTransform>();
        panelRect.anchorMin = Vector2.zero;
        panelRect.anchorMax = Vector2.one;
        panelRect.offsetMin = Vector2.zero;
        panelRect.offsetMax = Vector2.zero;

        MenuStyling.CreateBookPage(panelObject.transform, Vector2.zero, "Background");

        var contentObject = new GameObject("Content");
        contentObject.transform.SetParent(panelObject.transform, false);
        var rect = contentObject.AddComponent<RectTransform>();
        rect.anchorMin = new Vector2(0.08f, 0.08f);
        rect.anchorMax = new Vector2(0.92f, 0.92f);
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;
        contentRoot = rect;

        panelLayout = contentObject.AddComponent<VerticalLayoutGroup>();
        panelLayout.spacing = 12f;
        panelLayout.childControlHeight = true;
        panelLayout.childControlWidth = true;
        panelLayout.childForceExpandHeight = false;

        return rect;
    }

    private void CreateHeader(Transform parent, string text)
    {
        MenuStyling.CreateBookTitle(parent, text, new Vector2(0f, 56f), "Header");
    }

    private void CreateHeader(Transform parent, string text, float fontSize, float height)
    {
        var title = MenuStyling.CreateBookTitle(parent, text, new Vector2(0f, height), "Header");
        if (title != null)
        {
            title.fontSize = fontSize;
        }
    }

    private void CreateHeaderContainer(Transform parent, string text)
    {
        var headerObject = new GameObject("HeaderContainer");
        headerObject.transform.SetParent(parent, false);
        var rect = headerObject.AddComponent<RectTransform>();
        rect.anchorMin = new Vector2(0.5f, 1f);
        rect.anchorMax = new Vector2(0.5f, 1f);
        rect.pivot = new Vector2(0.5f, 1f);
        const float headerWidth = 720f;
        rect.sizeDelta = new Vector2(headerWidth, 100f);

        var layout = headerObject.AddComponent<LayoutElement>();
        layout.preferredHeight = 100f;
        layout.preferredWidth = headerWidth;

        var title = MenuStyling.CreateBookTitle(headerObject.transform, text, new Vector2(headerWidth, 120f), "Header");
        if (title != null)
        {
            title.fontSize = 72f;
            title.fontStyle = FontStyles.Bold;
        }
    }

    private void CreateText(Transform parent, string text)
    {
        var textObject = new GameObject("Text");
        textObject.transform.SetParent(parent, false);
        var tmp = textObject.AddComponent<TextMeshProUGUI>();
        tmp.text = text;
        tmp.fontSize = 20f;
        tmp.alignment = TextAlignmentOptions.Center;
        tmp.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : new Color(0.15f, 0.1f, 0.05f, 1f);

        var layout = textObject.AddComponent<LayoutElement>();
        layout.preferredHeight = 28f;
    }

    private void ConfigureCanvasScaler(Canvas canvas)
    {
        var scaler = canvas.GetComponent<CanvasScaler>();
        if (scaler == null)
        {
            scaler = canvas.gameObject.AddComponent<CanvasScaler>();
        }

        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920f, 1080f);
        scaler.screenMatchMode = CanvasScaler.ScreenMatchMode.MatchWidthOrHeight;
        scaler.matchWidthOrHeight = 0.5f;
    }

    private void CreateSpacer(Transform parent, float height)
    {
        var spacer = new GameObject("Spacer");
        spacer.transform.SetParent(parent, false);
        var layout = spacer.AddComponent<LayoutElement>();
        layout.preferredHeight = height;
    }

    private void CreateFlexibleSpacer(Transform parent)
    {
        var spacer = new GameObject("FlexibleSpacer");
        spacer.transform.SetParent(parent, false);
        var layout = spacer.AddComponent<LayoutElement>();
        layout.flexibleHeight = 1f;
    }

    private Button CreateButton(Transform parent, string label, Action onClick, float width, bool interactable, Sprite overrideSprite = null, float height = 44f)
    {
        var size = new Vector2(width, height);
        var button = MenuStyling.CreateBookButton(parent, label, size);
        button.interactable = interactable;
        if (!interactable)
        {
            button.image.color = buttonDisabledColor;
        }
        else if (overrideSprite != null)
        {
            button.image.sprite = overrideSprite;
        }
        else
        {
            button.image.sprite = MenuStyling.GetRoundedButtonSprite();
        }

        button.onClick.RemoveAllListeners();
        button.onClick.AddListener(() => onClick?.Invoke());
        return button;
    }

    private Button CreateBackButton(Transform parent, string label, Action onClick, float width, float height)
    {
        var button = CreateButton(parent, label, onClick, width, true, null, height);
        if (button != null && button.image != null)
        {
            button.image.sprite = MenuStyling.GetRoundedButtonSprite();
            button.image.type = Image.Type.Sliced;
            button.image.color = MenuStyling.Theme != null ? MenuStyling.Theme.parchmentBg : new Color(0.95f, 0.91f, 0.82f, 1f);
        }

        return button;
    }

    private Button CreateDeleteButton(Transform parent, string label, Action onClick, float width, float height)
    {
        var button = CreateButton(parent, label, onClick, width, true, null, height);
        if (button != null && button.image != null)
        {
            button.image.sprite = MenuStyling.GetRoundedButtonSprite();
            button.image.type = Image.Type.Sliced;
            button.image.color = new Color(0.65f, 0.15f, 0.15f, 1f);
        }
        var labelText = button != null ? button.GetComponentInChildren<TextMeshProUGUI>() : null;
        if (labelText != null)
        {
            labelText.color = Color.white;
        }

        return button;
    }

    private RectTransform CreateHorizontalGroup(Transform parent, float spacing, float height)
    {
        var row = new GameObject("ButtonRow");
        row.transform.SetParent(parent, false);
        var rect = row.AddComponent<RectTransform>();
        rect.anchorMin = new Vector2(0f, 0.5f);
        rect.anchorMax = new Vector2(1f, 0.5f);
        rect.pivot = new Vector2(0.5f, 0.5f);
        rect.sizeDelta = new Vector2(0f, height);

        var layout = row.AddComponent<HorizontalLayoutGroup>();
        layout.spacing = spacing;
        layout.childAlignment = TextAnchor.MiddleCenter;
        layout.childControlWidth = false;
        layout.childControlHeight = false;
        layout.childForceExpandWidth = false;
        layout.childForceExpandHeight = false;

        var element = row.AddComponent<LayoutElement>();
        element.preferredHeight = height;

        return rect;
    }

    private void SetLayoutAlignment(TextAnchor alignment)
    {
        if (panelLayout != null)
        {
            panelLayout.childAlignment = alignment;
        }
    }

    private void ConfigureMenuLayout()
    {
        if (panelLayout == null)
        {
            return;
        }

        panelLayout.childControlWidth = false;
        panelLayout.childForceExpandWidth = false;
    }

    private void SetContentTop(float topAnchor)
    {
        if (panelRoot == null)
        {
            return;
        }

        panelRoot.anchorMax = new Vector2(panelRoot.anchorMax.x, topAnchor);
        panelRoot.offsetMax = Vector2.zero;
    }

    private void SetContentOffsetY(float offset)
    {
        if (contentRoot == null)
        {
            return;
        }

        var position = contentRoot.anchoredPosition;
        position.y = offset;
        contentRoot.anchoredPosition = position;
      }
}
