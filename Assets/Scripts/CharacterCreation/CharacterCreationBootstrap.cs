using System;
using System.Collections.Generic;
using System.IO;
using TMPro;
#if UNITY_EDITOR
using UnityEditor;
#endif
using FableForge.Models;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using UnityColor = UnityEngine.Color;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem.UI;
#endif

public class CharacterCreationBootstrap : MonoBehaviour
{
    private static CharacterCreationBootstrap activeInstance;
    [SerializeField] private CharacterCreationController controller;
    [SerializeField] private TMP_FontAsset fallbackFont;
    [SerializeField] private TMP_FontAsset titleFontOverride;
    [SerializeField] private string rigId = "humanoid_v1";
    [Header("Character Preview")]
    [SerializeField] private GameObject previewRigPrefab;
    [SerializeField] private string previewLayerName = "CharacterPreviewRig";
    [SerializeField] private bool debugPreview = true;
    [SerializeField] private Vector2 previewSize = new Vector2(360f, 520f);
    [Header("AI Generation")]
    [SerializeField] private ReplicateImageService replicateService;
    [SerializeField] private string generatedOutputFolder = "GeneratedParts";
    [SerializeField] private bool allowGeneration = true;

    private TMP_FontAsset resolvedFont;
    private TMP_FontAsset titleFont;
    private Canvas canvas;
    private RectTransform panelRoot;
    private RawImage previewImage;
    private Camera previewCamera;
    private RenderTexture previewTexture;
    private GameObject previewRigInstance;
    private Button startGameButton;
    private bool isInitialized;
    private Sprite fallbackPreviewSprite;
    private FacingDirection currentFacing = FacingDirection.Front;
#if UNITY_EDITOR
    private Dictionary<string, string> manifestSpriteLookup;
#endif

    private readonly UnityColor buttonDisabledColor = new UnityColor(0.78f, 0.78f, 0.78f, 1f);

    private void Awake()
    {
        if (activeInstance != null && activeInstance != this)
        {
            Destroy(gameObject);
            return;
        }

        activeInstance = this;
    }

    private void OnDestroy()
    {
        if (activeInstance == this)
        {
            activeInstance = null;
        }
    }

    private void Start()
    {
        InitializeIfNeeded();
        BuildCurrentStep();
    }

    private void BuildCurrentStep()
    {
        ClearPanel();
        panelRoot = CreatePanel(canvas.transform);

        if (controller.Data == null || (controller.Data.Races.Count == 0 && controller.Data.Classes.Count == 0))
        {
            CreateHeader(panelRoot, "Character Creation");
            CreateText(panelRoot, "No data found. Add races/classes JSON to Resources/Prefabs/Character.");
            return;
        }

        switch (controller.CurrentStep)
        {
            case CharacterCreationController.CreationStep.RaceSelection:
                BuildRaceGenderScreen();
                break;
            case CharacterCreationController.CreationStep.Appearance:
                BuildAppearanceScreen();
                break;
        }
    }

    public void Activate()
    {
        InitializeIfNeeded();
        enabled = true;
        BuildCurrentStep();
    }

    public void Deactivate()
    {
        enabled = false;
        if (canvas != null)
        {
            canvas.enabled = false;
        }
        ClearPanel();
    }

    private void InitializeIfNeeded()
    {
        if (isInitialized)
        {
            return;
        }

        if (controller == null)
        {
            controller = GetComponent<CharacterCreationController>();
        }

        if (controller == null)
        {
            controller = gameObject.AddComponent<CharacterCreationController>();
        }

        if (LayerMask.GetMask(previewLayerName) == 0 && LayerMask.GetMask("CharacterPreviewRig") != 0)
        {
            previewLayerName = "CharacterPreviewRig";
        }

        resolvedFont = ResolveFont();
        titleFont = ResolveTitleFont();
        canvas = EnsureCanvas();
        EnsureEventSystem();
        controller.SetRigId(rigId);
        if (previewRigPrefab == null)
        {
            previewRigPrefab = Resources.Load<GameObject>("CharacterRigs/DefaultPreviewRig");
        }
        EnsureReplicateService();
        isInitialized = true;
    }

    private void EnsureReplicateService()
    {
        if (replicateService != null)
        {
            return;
        }

        replicateService = FindFirstObjectByType<ReplicateImageService>();
        if (replicateService == null)
        {
            replicateService = gameObject.AddComponent<ReplicateImageService>();
        }
    }

    private void BuildRaceGenderScreen()
    {
        CenterTitle(CreateHeader(panelRoot, "Character Creation"));
        CenterText(CreateText(panelRoot, SelectionSummary(), 18, TextAlignmentOptions.Center, 28f));
        CreateSpacer(panelRoot, 8f);

        var columnsRow = CreateHorizontalGroup(panelRoot, 520f, TextAnchor.UpperLeft);
        var columnsLayout = columnsRow.GetComponent<HorizontalLayoutGroup>();
        columnsLayout.childForceExpandWidth = true;

        var leftColumn = CreateVerticalGroup(columnsRow, 520f, 0f, TextAnchor.UpperCenter);
        var leftLayout = leftColumn.GetComponent<LayoutElement>();
        if (leftLayout != null)
        {
            leftLayout.flexibleWidth = 1f;
        }
        CreateHeader(leftColumn, "Choose Race", 30);
        CreateSpacer(leftColumn, 8f);

        foreach (var race in controller.Data.Races)
        {
            var raceId = race.id;
            var isSelected = controller.SelectedRace != null && controller.SelectedRace.id == raceId;
            CreateButton(leftColumn, race.name, () =>
            {
                controller.SelectRace(raceId);
                BuildCurrentStep();
            }, isSelected, 0f, true, UnityColor.white, true, true, 56f);
        }

        CreateRacePreview(columnsRow, 280f, true);

        CreateSpacer(panelRoot, 16f);

        var canContinue = controller.SelectedRace != null;
        var buttonRow = CreateHorizontalGroup(panelRoot, 44f, TextAnchor.MiddleCenter);
        CreateButton(buttonRow, "Back", () =>
        {
            ExitToMainMenu();
        }, false, 140f, true, null, true, false);
        CreateButton(buttonRow, "Continue", () =>
        {
            controller.CurrentStep = CharacterCreationController.CreationStep.Appearance;
            BuildCurrentStep();
        }, false, 180f, canContinue, null, true, false);
    }

    private void BuildAppearanceScreen()
    {
        if (!controller.SelectedGender.HasValue)
        {
            controller.SelectGender(CharacterCreationController.Gender.Male);
        }
        CenterTitle(CreateHeader(panelRoot, "Character Appearance"));
        if (debugPreview)
        {
            Debug.Log($"[AppearanceScreen] Build: race={controller.SelectedRace?.id ?? "none"}, gender={controller.SelectedGender?.ToString() ?? "none"}, name='{controller.CharacterName}'");
        }
        CenterText(CreateText(panelRoot, SelectionSummary(), 18, TextAlignmentOptions.Center, 28f));
        CreateSpacer(panelRoot, 8f);

        var nameRow = CreateHorizontalGroup(panelRoot, 80f, TextAnchor.MiddleCenter);
        CreateFlexibleSpacer(nameRow);
        var nameColumn = CreateVerticalGroup(nameRow, 0f, 0f, TextAnchor.UpperCenter);
        var nameLayout = nameColumn.GetComponent<LayoutElement>();
        if (nameLayout != null)
        {
            nameLayout.preferredWidth = 300f;
            nameLayout.minWidth = 300f;
            nameLayout.flexibleWidth = 0f;
        }
        CreateInputField(nameColumn, "Character Name", controller.CharacterName, false, value =>
        {
            controller.CharacterName = value;
            UpdateStartButtonState();
        }, 300f, 36f, TextAlignmentOptions.Center);
        CreateFlexibleSpacer(nameRow);

        CreateSpacer(panelRoot, 6f);
        var genderRow = CreateHorizontalGroup(panelRoot, 48f, TextAnchor.MiddleCenter);
        CreateFlexibleSpacer(genderRow);
        var genderGroupObject = new GameObject("GenderButtons");
        genderGroupObject.transform.SetParent(genderRow, false);
        var genderGroupRect = genderGroupObject.AddComponent<RectTransform>();
        var genderGroupLayout = genderGroupObject.AddComponent<HorizontalLayoutGroup>();
        genderGroupLayout.spacing = 8f;
        genderGroupLayout.childControlWidth = true;
        genderGroupLayout.childControlHeight = true;
        genderGroupLayout.childForceExpandWidth = false;
        genderGroupLayout.childForceExpandHeight = false;
        genderGroupLayout.childAlignment = TextAnchor.MiddleCenter;
        var genderGroupElement = genderGroupObject.AddComponent<LayoutElement>();
        genderGroupElement.preferredWidth = 346f;
        genderGroupElement.minWidth = 346f;
        genderGroupElement.flexibleWidth = 0f;

        foreach (CharacterCreationController.Gender gender in Enum.GetValues(typeof(CharacterCreationController.Gender)))
        {
            var genderValue = gender;
            var isSelected = controller.SelectedGender.HasValue && controller.SelectedGender.Value == genderValue;
            CreateButton(genderGroupObject.transform, gender.ToString(), () =>
            {
                controller.SelectGender(genderValue);
                BuildCurrentStep();
            }, isSelected, 110f, true, UnityColor.white, true, true, 44f);
        }
        CreateFlexibleSpacer(genderRow);

        CreateSpacer(panelRoot, 8f);

        var columnsRow = CreateHorizontalGroup(panelRoot, 620f, TextAnchor.UpperLeft);
        var columnsLayout = columnsRow.GetComponent<HorizontalLayoutGroup>();
        columnsLayout.childForceExpandWidth = true;
        columnsLayout.childControlWidth = true;
        columnsLayout.childControlHeight = true;
        columnsLayout.childForceExpandHeight = false;

        var leftColumn = CreateVerticalGroup(columnsRow, 620f, 0f, TextAnchor.UpperLeft);
        var leftLayout = leftColumn.GetComponent<LayoutElement>();
        if (leftLayout != null)
        {
            leftLayout.flexibleWidth = 1f;
            leftLayout.minWidth = 320f;
        }
        var leftColumnLayout = leftColumn.GetComponent<VerticalLayoutGroup>();
        if (leftColumnLayout != null)
        {
            leftColumnLayout.childForceExpandHeight = true;
            leftColumnLayout.childControlWidth = true;
            leftColumnLayout.childForceExpandWidth = true;
        }

        CreateScrollableAppearanceOptions(leftColumn);

        var rightColumn = CreateVerticalGroup(columnsRow, 620f, 0f, TextAnchor.UpperCenter);
        var rightLayout = rightColumn.GetComponent<LayoutElement>();
        if (rightLayout != null)
        {
            rightLayout.flexibleWidth = 1f;
            rightLayout.minWidth = 320f;
        }
        var rightColumnLayout = rightColumn.GetComponent<VerticalLayoutGroup>();
        if (rightColumnLayout != null)
        {
            rightColumnLayout.childControlWidth = true;
            rightColumnLayout.childForceExpandWidth = true;
        }

        CreateSpritePreview(rightColumn);
        CreateFacingControls(rightColumn);
        CreateSpacer(rightColumn, 12f);

        if (controller.IsGeneratingImage)
        {
            CreateText(panelRoot, "Generating image... please wait.", 14, TextAlignmentOptions.Center, 22f);
        }
        else if (!string.IsNullOrWhiteSpace(controller.GenerationError))
        {
            CreateText(panelRoot, $"Generation failed: {controller.GenerationError}", 14, TextAlignmentOptions.Center, 22f);
        }
        else if (!string.IsNullOrWhiteSpace(controller.LastGeneratedPath))
        {
            CreateText(panelRoot, $"Saved to: {controller.LastGeneratedPath}", 14, TextAlignmentOptions.Center, 22f);
        }

        var buttonRow = CreateHorizontalGroup(panelRoot);
        CreateButton(buttonRow, "Back", () =>
        {
            controller.CurrentStep = CharacterCreationController.CreationStep.RaceSelection;
            BuildCurrentStep();
        }, false, 120f, true, null, true, false);
        var canStart = !string.IsNullOrWhiteSpace(controller.CharacterName);
        startGameButton = CreateButton(buttonRow, "Start Game", () =>
        {
            if (string.IsNullOrWhiteSpace(controller.CharacterName))
            {
                return;
            }

            Deactivate();
            controller.SaveToSelectedSlot();
            GameFlow.StartNewGame(controller.BuildGameCharacter());
            Debug.Log("Character creation complete. Saved to selected slot.");
        }, false, 260f, canStart, null, true, false);
    }

    private void CreateScrollableAppearanceOptions(Transform parent)
    {
        if (debugPreview)
        {
            Debug.Log("[AppearanceScreen] Building scrollable options...");
        }
        var scrollObject = new GameObject("AppearanceScroll");
        scrollObject.transform.SetParent(parent, false);

        var scrollRect = scrollObject.AddComponent<RectTransform>();
        scrollRect.anchorMin = new Vector2(0f, 0f);
        scrollRect.anchorMax = new Vector2(1f, 1f);
        scrollRect.offsetMin = Vector2.zero;
        scrollRect.offsetMax = Vector2.zero;
        scrollRect.sizeDelta = Vector2.zero;

        var layout = scrollObject.AddComponent<LayoutElement>();
        layout.preferredHeight = 520f;
        layout.flexibleHeight = 1f;
        layout.minHeight = 320f;

        var scrollBackground = scrollObject.AddComponent<Image>();
        scrollBackground.color = new UnityColor(0f, 0f, 0f, 0.03f);

        var scroll = scrollObject.AddComponent<ScrollRect>();
        scroll.horizontal = false;
        scroll.vertical = true;
        scroll.movementType = ScrollRect.MovementType.Clamped;

        var viewportObject = new GameObject("Viewport");
        viewportObject.transform.SetParent(scrollObject.transform, false);
        var viewportRect = viewportObject.AddComponent<RectTransform>();
        viewportRect.anchorMin = Vector2.zero;
        viewportRect.anchorMax = Vector2.one;
        viewportRect.offsetMin = Vector2.zero;
        viewportRect.offsetMax = Vector2.zero;
        viewportObject.AddComponent<RectMask2D>();
        var viewportImage = viewportObject.AddComponent<Image>();
        viewportImage.color = new UnityColor(0f, 0f, 0f, 0.05f);

        var contentObject = new GameObject("Content");
        contentObject.transform.SetParent(viewportObject.transform, false);
        var contentRect = contentObject.AddComponent<RectTransform>();
        contentRect.anchorMin = new Vector2(0f, 1f);
        contentRect.anchorMax = new Vector2(1f, 1f);
        contentRect.pivot = new Vector2(0.5f, 1f);
        contentRect.offsetMin = Vector2.zero;
        contentRect.offsetMax = Vector2.zero;

        var contentLayout = contentObject.AddComponent<VerticalLayoutGroup>();
        contentLayout.spacing = 6f;
        contentLayout.childControlHeight = true;
        contentLayout.childForceExpandHeight = false;
        contentLayout.childControlWidth = true;
        contentLayout.childForceExpandWidth = true;

        contentObject.AddComponent<ContentSizeFitter>().verticalFit = ContentSizeFitter.FitMode.PreferredSize;

        scroll.viewport = viewportRect;
        scroll.content = contentRect;
        scrollRect.SetAsLastSibling();

        CreateAppearanceOptions(contentObject.transform);
    }

    private void CreateAppearanceOptions(Transform parent)
    {
        var definitions = controller.GetAppearanceDefinitions();
        if (debugPreview)
        {
            Debug.Log($"[AppearanceScreen] Options definitions count: {definitions?.Count ?? 0}");
        }
        if (definitions == null || definitions.Count == 0)
        {
            CreateText(parent, "No appearance options configured for this race/gender.");
            return;
        }

        foreach (var definition in definitions)
        {
            if (definition.category == AppearanceCategory.Body || definition.category == AppearanceCategory.Weight)
            {
                continue;
            }
            if (definition.options == null || definition.options.Count == 0)
            {
                continue;
            }

            if (definition.category == AppearanceCategory.Height
                || definition.category == AppearanceCategory.Weight
                || definition.category == AppearanceCategory.Build)
            {
                CreateSliderOption(parent, definition);
            }
            else
            {
                CreateCarouselOption(parent, definition);
            }

            CreateSpacer(parent, 6f);
        }
    }

    private void CreateSliderOption(Transform parent, AppearanceCategoryDefinition definition)
    {
        CreateText(parent, definition.label, 16, TextAlignmentOptions.MidlineLeft, 22f, FontStyles.Bold);

        var row = CreateHorizontalGroup(parent, 44f, TextAnchor.MiddleLeft);
        var selectedIndex = GetSelectedOptionIndex(definition);

        var sliderObject = new GameObject($"{definition.category}_Slider");
        sliderObject.transform.SetParent(row, false);
        var sliderRect = sliderObject.AddComponent<RectTransform>();
        sliderRect.sizeDelta = new Vector2(260f, 28f);
        var sliderLayout = sliderObject.AddComponent<LayoutElement>();
        sliderLayout.preferredWidth = 260f;
        sliderLayout.preferredHeight = 28f;

        var slider = sliderObject.AddComponent<Slider>();
        slider.minValue = 0;
        slider.maxValue = 10;
        slider.wholeNumbers = true;
        slider.value = controller.GetSliderValue(definition.category);

        var sliderImage = sliderObject.AddComponent<Image>();
        sliderImage.color = new UnityColor(0f, 0f, 0f, 0f);
        slider.targetGraphic = sliderImage;

        var background = new GameObject("Background");
        background.transform.SetParent(sliderObject.transform, false);
        var backgroundImage = background.AddComponent<Image>();
        backgroundImage.color = new UnityColor(0.25f, 0.2f, 0.15f, 1f);
        var backgroundRect = background.GetComponent<RectTransform>();
        backgroundRect.anchorMin = Vector2.zero;
        backgroundRect.anchorMax = Vector2.one;
        backgroundRect.offsetMin = new Vector2(6f, 10f);
        backgroundRect.offsetMax = new Vector2(-6f, -10f);

        var fillArea = new GameObject("FillArea");
        fillArea.transform.SetParent(sliderObject.transform, false);
        var fillRect = fillArea.AddComponent<RectTransform>();
        fillRect.anchorMin = new Vector2(0f, 0f);
        fillRect.anchorMax = new Vector2(1f, 1f);
        fillRect.offsetMin = new Vector2(6f, 10f);
        fillRect.offsetMax = new Vector2(-6f, -10f);

        var fill = new GameObject("Fill");
        fill.transform.SetParent(fillArea.transform, false);
        var fillImage = fill.AddComponent<Image>();
        fillImage.color = new UnityColor(0.75f, 0.6f, 0.3f, 1f);
        var fillImageRect = fill.GetComponent<RectTransform>();
        fillImageRect.anchorMin = Vector2.zero;
        fillImageRect.anchorMax = Vector2.one;
        fillImageRect.offsetMin = Vector2.zero;
        fillImageRect.offsetMax = Vector2.zero;

        var handle = new GameObject("Handle");
        handle.transform.SetParent(sliderObject.transform, false);
        var handleImage = handle.AddComponent<Image>();
        handleImage.color = UnityColor.white;
        var handleRect = handle.GetComponent<RectTransform>();
        handleRect.sizeDelta = new Vector2(18f, 18f);
        handleRect.anchorMin = new Vector2(0f, 0.5f);
        handleRect.anchorMax = new Vector2(0f, 0.5f);

        slider.fillRect = fillImageRect;
        slider.handleRect = handleRect;
        slider.direction = Slider.Direction.LeftToRight;

        slider.onValueChanged.AddListener(value =>
        {
            controller.SetSliderValue(definition.category, value);
            var index = definition.options.Count > 0
                ? Mathf.Clamp(Mathf.RoundToInt((value / 10f) * (definition.options.Count - 1)), 0, definition.options.Count - 1)
                : 0;
            if (definition.options.Count > 0)
            {
                var option = definition.options[index];
                controller.SelectAppearanceOption(definition.category, option.id);
            }
            ApplyPreviewScale();
        });
    }

    private void UpdateStartButtonState()
    {
        if (startGameButton == null)
        {
            return;
        }

        var canStart = !string.IsNullOrWhiteSpace(controller.CharacterName);
        startGameButton.interactable = canStart;
        var image = startGameButton.GetComponent<Image>();
        if (image != null)
        {
            image.color = canStart ? UnityColor.white : buttonDisabledColor;
        }
    }

    private void CreateFacingControls(Transform parent)
    {
        var row = CreateHorizontalGroup(parent, 36f, TextAnchor.MiddleCenter);
        CreateButton(row, "<", () =>
        {
            RotateFacing(-1);
        }, false, 36f, true, UnityColor.white, true, true, 32f);
        CreateText(row, "Rotate", 14, TextAlignmentOptions.MidlineLeft, 24f, FontStyles.Bold);
        CreateButton(row, ">", () =>
        {
            RotateFacing(1);
        }, false, 36f, true, UnityColor.white, true, true, 32f);
    }

    private void RotateFacing(int direction)
    {
        var order = new[] { FacingDirection.Front, FacingDirection.Side, FacingDirection.Back };
        var index = Array.IndexOf(order, currentFacing);
        if (index < 0)
        {
            index = 0;
        }
        index = (index + direction + order.Length) % order.Length;
        currentFacing = order[index];
        ApplyFacingToPreview();
    }

    private void ApplyFacingToPreview()
    {
        if (previewRigInstance == null)
        {
            return;
        }

        var preset = CharacterPreset.FromSelections(
            rigId,
            controller.AppearanceSelections,
            controller.GetAppearanceDefinitions());

        var resolver = previewRigInstance.GetComponent<FacingDirectionResolver>();
        if (resolver == null)
        {
            resolver = previewRigInstance.AddComponent<FacingDirectionResolver>();
        }

        resolver.SetFacing(currentFacing, preset.slots);
#if UNITY_EDITOR
        ApplyManifestSpriteOverride(preset.slots);
#endif
        if (previewCamera != null)
        {
            previewCamera.Render();
        }
    }

    private void ApplyPreviewScale()
    {
        if (previewRigInstance == null)
        {
            return;
        }

        var heightValue = controller.GetSliderValue(AppearanceCategory.Height);
        var buildValue = controller.GetSliderValue(AppearanceCategory.Build);

        var heightScale = Mathf.Lerp(0.85f, 1.25f, heightValue / 10f);
        var buildScale = Mathf.Lerp(0.7f, 1.35f, buildValue / 10f);

        var finalScale = new Vector3(buildScale, heightScale, 1f);
        previewRigInstance.transform.localScale = finalScale;
        UpdatePreviewCameraForScale(finalScale);
        if (previewCamera != null)
        {
            previewCamera.Render();
        }
    }

    private void UpdatePreviewCameraForScale(Vector3 scale)
    {
        if (previewCamera == null)
        {
            return;
        }

        var baseSize = Mathf.Max(2.6f, previewSize.y / 220f);
        var zoomForWidth = Mathf.Lerp(1f, 1.25f, Mathf.Clamp01((scale.x - 1f) / 0.4f));
        var zoomForHeight = Mathf.Lerp(1f, 1.35f, Mathf.Clamp01((scale.y - 1f) / 0.4f));
        previewCamera.orthographicSize = baseSize * Mathf.Max(zoomForWidth, zoomForHeight);
        var heightOffset = Mathf.Lerp(0.2f, -0.15f, Mathf.Clamp01((scale.y - 1f) / 0.5f));
        previewCamera.transform.position = new Vector3(0f, heightOffset, -10f);
    }

    private void LogBodyPreviewStatus()
    {
        if (!debugPreview || previewRigInstance == null)
        {
            return;
        }

        var preset = CharacterPreset.FromSelections(
            rigId,
            controller.AppearanceSelections,
            controller.GetAppearanceDefinitions());

        preset.slots.TryGetValue("Body", out var bodyLabel);
        var library = previewRigInstance.GetComponent<UnityEngine.U2D.Animation.SpriteLibrary>();
        var resolver = Array.Find(previewRigInstance.GetComponentsInChildren<UnityEngine.U2D.Animation.SpriteResolver>(true),
            item => item != null && item.GetCategory() == "Body");
        var renderer = resolver != null ? resolver.GetComponent<SpriteRenderer>() : null;
        var sprite = (library != null && library.spriteLibraryAsset != null && !string.IsNullOrWhiteSpace(bodyLabel))
            ? library.spriteLibraryAsset.GetSprite("Body", bodyLabel)
            : null;
#if UNITY_EDITOR
        var manifestSprite = TryLoadSpriteFromManifest("Body", bodyLabel);
#else
        Sprite manifestSprite = null;
#endif

        Debug.Log($"[Preview] Body label='{bodyLabel ?? "null"}' librarySprite={(sprite != null ? sprite.name : "null")} manifestSprite={(manifestSprite != null ? manifestSprite.name : "null")} resolverSprite={(renderer != null && renderer.sprite != null ? renderer.sprite.name : "null")}");
    }

#if UNITY_EDITOR
    private void ApplyManifestSpriteOverride(Dictionary<string, string> slots)
    {
        if (slots == null || previewRigInstance == null)
        {
            return;
        }

        foreach (var entry in slots)
        {
            if (string.IsNullOrWhiteSpace(entry.Key) || string.IsNullOrWhiteSpace(entry.Value))
            {
                continue;
            }

            var sprite = TryLoadSpriteFromManifest(entry.Key, entry.Value);
            if (sprite == null)
            {
                continue;
            }

            ApplySpriteToCategory(entry.Key, sprite);
        }
    }

    private Sprite TryLoadSpriteFromManifest(string category, string label)
    {
        if (string.IsNullOrWhiteSpace(category) || string.IsNullOrWhiteSpace(label))
        {
            return null;
        }

        if (manifestSpriteLookup == null)
        {
            manifestSpriteLookup = new Dictionary<string, string>();
            var manifestPath = Path.Combine(Application.dataPath, "Data/CharacterParts/parts_manifest.json");
            if (File.Exists(manifestPath))
            {
                var json = File.ReadAllText(manifestPath);
                var parsed = MiniJson.Deserialize(json) as Dictionary<string, object>;
                if (parsed != null && parsed.TryGetValue("categories", out var categoriesObj) && categoriesObj is Dictionary<string, object> categoriesDict)
                {
                    foreach (var categoryEntry in categoriesDict)
                    {
                        if (categoryEntry.Value is List<object> list)
                        {
                            foreach (var item in list)
                            {
                                if (item is Dictionary<string, object> entryDict)
                                {
                                    var entryLabel = entryDict.TryGetValue("label", out var labelObj) ? labelObj as string : null;
                                    var entryPath = entryDict.TryGetValue("path", out var pathObj) ? pathObj as string : null;
                                    if (!string.IsNullOrWhiteSpace(entryLabel) && !string.IsNullOrWhiteSpace(entryPath))
                                    {
                                        var key = $"{categoryEntry.Key}|{entryLabel}";
                                        manifestSpriteLookup[key] = entryPath;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        var lookupKey = $"{category}|{label}";
        if (!manifestSpriteLookup.TryGetValue(lookupKey, out var assetPath))
        {
            if (debugPreview)
            {
                Debug.Log($"[Preview] Manifest lookup missing key {lookupKey}");
            }
            return null;
        }

        var sprite = AssetDatabase.LoadAssetAtPath<Sprite>(assetPath);
        if (sprite != null)
        {
            return sprite;
        }

        var importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
        if (importer != null)
        {
            importer.textureType = TextureImporterType.Sprite;
            importer.spritePixelsPerUnit = 100f;
            importer.mipmapEnabled = false;
            importer.alphaIsTransparency = true;
            importer.SaveAndReimport();
            sprite = AssetDatabase.LoadAssetAtPath<Sprite>(assetPath);
        }

        if (sprite == null && debugPreview)
        {
            Debug.LogWarning($"[Preview] Manifest sprite not found at {assetPath}");
        }

        return sprite;
    }
#endif

    private void CreateCarouselOption(Transform parent, AppearanceCategoryDefinition definition)
    {
        CreateText(parent, definition.label, 16, TextAlignmentOptions.MidlineLeft, 22f, FontStyles.Bold);

        var row = CreateHorizontalGroup(parent, 44f, TextAnchor.MiddleLeft);
        var selectedIndex = GetSelectedOptionIndex(definition);
        var selectedOption = definition.options[selectedIndex];

        CreateButton(row, "<", () =>
        {
            SelectOptionByDelta(definition, -1);
        }, false, 32f, true, UnityColor.white, true, true, 36f);

        var previewObject = new GameObject($"{definition.category}_Preview");
        previewObject.transform.SetParent(row, false);
        var previewRect = previewObject.AddComponent<RectTransform>();
        previewRect.sizeDelta = new Vector2(46f, 46f);
        var previewImage = previewObject.AddComponent<Image>();
        previewImage.color = new UnityColor(0.2f, 0.2f, 0.2f, 1f);
        var previewSprite = GetPreviewSprite(selectedOption);
        if (previewSprite != null)
        {
            previewImage.sprite = previewSprite;
            previewImage.preserveAspect = true;
            previewImage.color = UnityColor.white;
        }

        CreateButton(row, ">", () =>
        {
            SelectOptionByDelta(definition, 1);
        }, false, 32f, true, UnityColor.white, true, true, 36f);

        if (allowGeneration)
        {
            CreateButton(row, "+", () =>
            {
                if (controller.IsGeneratingImage)
                {
                    return;
                }

                StartCoroutine(GenerateOptionImage(definition, selectedOption));
            }, false, 46f, !controller.IsGeneratingImage, UnityColor.white, true, true, 36f);
        }
    }

    private int GetSelectedOptionIndex(AppearanceCategoryDefinition definition)
    {
        var selected = controller.GetSelectedAppearanceOption(definition.category);
        if (selected == null)
        {
            return 0;
        }

        var index = definition.options.FindIndex(option => option.id == selected.id);
        return index >= 0 ? index : 0;
    }

    private void SelectOptionByDelta(AppearanceCategoryDefinition definition, int delta)
    {
        var currentIndex = GetSelectedOptionIndex(definition);
        var nextIndex = currentIndex + delta;
        if (nextIndex < 0)
        {
            nextIndex = definition.options.Count - 1;
        }
        else if (nextIndex >= definition.options.Count)
        {
            nextIndex = 0;
        }

        var option = definition.options[nextIndex];
        controller.SelectAppearanceOption(definition.category, option.id);
        BuildCurrentStep();
    }

    private Sprite GetPreviewSprite(AppearanceOptionDefinition option)
    {
        if (previewRigInstance == null || option == null)
        {
            return null;
        }

        if (option.runtimeSprite != null)
        {
            return option.runtimeSprite;
        }

        var library = previewRigInstance.GetComponent<UnityEngine.U2D.Animation.SpriteLibrary>();
        if (library == null || library.spriteLibraryAsset == null)
        {
            return GetFallbackPreviewSprite();
        }

        if (string.IsNullOrWhiteSpace(option.slotCategory) || string.IsNullOrWhiteSpace(option.slotLabel))
        {
            return GetFallbackPreviewSprite();
        }

        var sprite = library.spriteLibraryAsset.GetSprite(option.slotCategory, option.slotLabel);
        if (sprite != null)
        {
            return sprite;
        }

#if UNITY_EDITOR
        var manifestSprite = TryLoadSpriteFromManifest(option.slotCategory, option.slotLabel);
        if (manifestSprite != null)
        {
            return manifestSprite;
        }
#endif

        return GetFallbackPreviewSprite();
    }

    private void EnsurePreviewPlaceholderSprites()
    {
        if (previewRigInstance == null)
        {
            return;
        }

        var fallback = GetFallbackPreviewSprite();
        if (fallback == null)
        {
            return;
        }

        var renderers = previewRigInstance.GetComponentsInChildren<SpriteRenderer>(true);
        foreach (var renderer in renderers)
        {
            if (renderer != null && renderer.sprite == null)
            {
                renderer.sprite = fallback;
            }
        }
    }

    private Sprite GetFallbackPreviewSprite()
    {
        if (fallbackPreviewSprite != null)
        {
            return fallbackPreviewSprite;
        }

        var texture = new Texture2D(64, 64, TextureFormat.RGBA32, false);
        var light = new UnityColor(0.9f, 0.86f, 0.8f, 1f);
        var dark = new UnityColor(0.75f, 0.7f, 0.62f, 1f);
        for (var y = 0; y < texture.height; y++)
        {
            for (var x = 0; x < texture.width; x++)
            {
                var checker = ((x / 8) + (y / 8)) % 2 == 0;
                texture.SetPixel(x, y, checker ? light : dark);
            }
        }
        texture.Apply();

        fallbackPreviewSprite = Sprite.Create(texture, new Rect(0f, 0f, texture.width, texture.height), new Vector2(0.5f, 0.5f), 100f);
        return fallbackPreviewSprite;
    }

    private string SelectionSummary()
    {
        var race = controller.SelectedRace != null ? controller.SelectedRace.name : "No Race";
        var gender = controller.SelectedGender.HasValue ? controller.SelectedGender.Value.ToString() : "No Gender";
        return $"{race} - {gender}";
    }

    private Canvas EnsureCanvas()
    {
        var canvases = Resources.FindObjectsOfTypeAll<Canvas>();
        foreach (var canvas in canvases)
        {
            if (canvas != null && canvas.name == "CharacterCreationCanvas")
            {
                ConfigureCanvasScaler(canvas);
                canvas.enabled = true;
                canvas.gameObject.SetActive(true);
                if (canvas.GetComponent<GraphicRaycaster>() == null)
                {
                    canvas.gameObject.AddComponent<GraphicRaycaster>();
                }
                return canvas;
            }
        }

        var canvasObject = new GameObject("CharacterCreationCanvas");
        var createdCanvas = canvasObject.AddComponent<Canvas>();
        createdCanvas.renderMode = RenderMode.ScreenSpaceOverlay;
        ConfigureCanvasScaler(createdCanvas);
        canvasObject.AddComponent<GraphicRaycaster>();
        return createdCanvas;
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

    private void CreateSpritePreview(Transform parent)
    {
        if (debugPreview)
        {
            Debug.Log($"[Preview] prefab={(previewRigPrefab != null ? previewRigPrefab.name : "null")}, layer='{previewLayerName}', size={previewSize}");
        }
        EnsurePreviewCamera();
        EnsurePreviewTarget(parent);

        if (previewRigPrefab == null)
        {
            CreateText(parent, "Assign a preview rig prefab to show the character.", 14, TextAlignmentOptions.Center, 24f);
            if (debugPreview)
            {
                Debug.LogWarning("[Preview] previewRigPrefab is null.");
            }
            return;
        }

        if (previewRigInstance == null)
        {
            previewRigInstance = Instantiate(previewRigPrefab);
            previewRigInstance.name = "CharacterPreviewRig";
            previewRigInstance.transform.position = Vector3.zero;
            previewRigInstance.transform.rotation = Quaternion.identity;
            ApplyPreviewLayer(previewRigInstance);
            if (debugPreview)
            {
                Debug.Log("[Preview] Instantiated preview rig.");
            }
        }

        var customizer = previewRigInstance.GetComponent<CharacterCustomizer>();
        if (customizer == null)
        {
            customizer = previewRigInstance.AddComponent<CharacterCustomizer>();
        }

        var preset = CharacterPreset.FromSelections(
            rigId,
            controller.AppearanceSelections,
            controller.GetAppearanceDefinitions());
        EnsureResolverCategoriesFromNames(preset.slots);
        customizer.ApplyPreset(preset);

        ApplyRuntimeSpritesForSelections();
        EnsurePreviewPlaceholderSprites();
        ApplyFacingToPreview();
        ApplyPreviewScale();
        LogBodyPreviewStatus();
        previewCamera.Render();

        if (previewRigInstance.GetComponentInChildren<SpriteRenderer>() == null)
        {
            CreateText(parent, "Preview rig has no SpriteRenderers.", 14, TextAlignmentOptions.Center, 24f);
            if (debugPreview)
            {
                Debug.LogWarning("[Preview] No SpriteRenderer found in preview rig.");
            }
        }
        else if (debugPreview)
        {
            var rendererCount = previewRigInstance.GetComponentsInChildren<SpriteRenderer>(true).Length;
            Debug.Log($"[Preview] SpriteRenderers found: {rendererCount}");
        }
    }

    private void ApplyRuntimeSpritesForSelections()
    {
        var definitions = controller.GetAppearanceDefinitions();
        foreach (var definition in definitions)
        {
            var selected = controller.GetSelectedAppearanceOption(definition.category);
            if (selected != null && selected.runtimeSprite != null)
            {
                ApplySpriteToCategory(selected.slotCategory, selected.runtimeSprite);
                if (!string.IsNullOrWhiteSpace(selected.slotCategorySecondary))
                {
                    ApplySpriteToCategory(selected.slotCategorySecondary, selected.runtimeSprite);
                }
            }
        }
    }

    private void EnsureResolverCategoriesFromNames(Dictionary<string, string> slots)
    {
        if (previewRigInstance == null || slots == null)
        {
            return;
        }

        var resolvers = previewRigInstance.GetComponentsInChildren<UnityEngine.U2D.Animation.SpriteResolver>(true);
        foreach (var resolver in resolvers)
        {
            if (resolver == null)
            {
                continue;
            }

            var category = resolver.GetCategory();
            if (!string.IsNullOrWhiteSpace(category))
            {
                continue;
            }

            var inferred = resolver.gameObject.name;
            if (string.IsNullOrWhiteSpace(inferred))
            {
                continue;
            }

            if (slots.TryGetValue(inferred, out var label) && !string.IsNullOrWhiteSpace(label))
            {
                resolver.SetCategoryAndLabel(inferred, label);
            }
            else
            {
                resolver.SetCategoryAndLabel(inferred, "placeholder");
            }
        }
    }

    private void EnsurePreviewCamera()
    {
        if (previewCamera != null)
        {
            return;
        }

        if (LayerMask.GetMask(previewLayerName) == 0 && LayerMask.GetMask("CharacterPreviewRig") != 0)
        {
            previewLayerName = "CharacterPreviewRig";
        }

        var cameraObject = new GameObject("CharacterPreviewCamera");
        previewCamera = cameraObject.AddComponent<Camera>();
        previewCamera.orthographic = true;
        previewCamera.orthographicSize = Mathf.Max(2.6f, previewSize.y / 220f);
        previewCamera.clearFlags = CameraClearFlags.SolidColor;
        previewCamera.backgroundColor = new UnityColor(0f, 0f, 0f, 0f);
        var mask = LayerMask.GetMask(previewLayerName);
        if (mask == 0)
        {
            if (debugPreview)
            {
                Debug.LogWarning($"[Preview] Layer '{previewLayerName}' not found. Rendering all layers.");
            }
            previewCamera.cullingMask = ~0;
        }
        else
        {
            previewCamera.cullingMask = mask;
        }
        previewCamera.depth = 10f;
        previewCamera.transform.position = new Vector3(0f, 0.2f, -10f);
        if (debugPreview)
        {
            Debug.Log($"[Preview] Camera created. cullingMask={previewCamera.cullingMask}");
        }
    }

    private void EnsurePreviewTarget(Transform parent)
    {
        if (previewImage == null)
        {
            var previewObject = new GameObject("CharacterPreview");
            previewObject.transform.SetParent(parent, false);
            var rect = previewObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0f, 0f);
            rect.anchorMax = new Vector2(1f, 0f);
            rect.sizeDelta = new Vector2(0f, previewSize.y);

            var layout = previewObject.AddComponent<LayoutElement>();
            layout.preferredHeight = previewSize.y;
            layout.preferredWidth = previewSize.x;
            layout.minHeight = previewSize.y;
            layout.minWidth = previewSize.x;
            layout.flexibleHeight = 1f;
            layout.flexibleWidth = 1f;

            var backgroundObject = new GameObject("PreviewBackground");
            backgroundObject.transform.SetParent(previewObject.transform, false);
            var backgroundRect = backgroundObject.AddComponent<RectTransform>();
            backgroundRect.anchorMin = Vector2.zero;
            backgroundRect.anchorMax = Vector2.one;
            backgroundRect.offsetMin = Vector2.zero;
            backgroundRect.offsetMax = Vector2.zero;
            var background = backgroundObject.AddComponent<Image>();
            background.color = new UnityColor(0f, 0f, 0f, 0f);

            var imageObject = new GameObject("PreviewImage");
            imageObject.transform.SetParent(previewObject.transform, false);
            var imageRect = imageObject.AddComponent<RectTransform>();
            imageRect.anchorMin = Vector2.zero;
            imageRect.anchorMax = Vector2.one;
            imageRect.offsetMin = Vector2.zero;
            imageRect.offsetMax = Vector2.zero;
            previewImage = imageObject.AddComponent<RawImage>();
            previewImage.color = UnityColor.white;
            previewImage.raycastTarget = false;

            var fitter = imageObject.AddComponent<AspectRatioFitter>();
            fitter.aspectRatio = Mathf.Approximately(previewSize.y, 0f) ? 1f : (previewSize.x / previewSize.y);
            fitter.aspectMode = AspectRatioFitter.AspectMode.FitInParent;

            if (debugPreview)
            {
                Debug.Log("[Preview] RawImage created for preview.");
            }
        }

        if (previewTexture == null)
        {
            previewTexture = new RenderTexture((int)previewSize.x, (int)previewSize.y, 16)
            {
                name = "CharacterPreviewRT"
            };
            if (debugPreview)
            {
                Debug.Log($"[Preview] RenderTexture created {previewSize.x}x{previewSize.y}");
            }
        }

        previewImage.texture = previewTexture;
        previewCamera.targetTexture = previewTexture;
        if (debugPreview)
        {
            Debug.Log("[Preview] Preview target assigned.");
        }
    }

    private void ApplyPreviewLayer(GameObject target)
    {
        var layer = LayerMask.NameToLayer(previewLayerName);
        if (layer < 0)
        {
            layer = 0;
        }

        var transforms = target.GetComponentsInChildren<Transform>(true);
        foreach (var child in transforms)
        {
            child.gameObject.layer = layer;
        }
    }

    private System.Collections.IEnumerator GenerateOptionImage(AppearanceCategoryDefinition definition, AppearanceOptionDefinition option)
    {
        EnsureReplicateService();
        if (replicateService == null)
        {
            controller.GenerationError = "Replicate service not available.";
            BuildCurrentStep();
            yield break;
        }

        controller.IsGeneratingImage = true;
        controller.GenerationError = null;
        controller.LastGeneratedPath = null;
        BuildCurrentStep();

        var prompt = BuildReplicatePrompt(definition, option);
        Texture2D generated = null;
        string error = null;

        replicateService.GenerateImage(prompt, (texture, err) =>
        {
            generated = texture;
            error = err;
        });

        while (generated == null && error == null)
        {
            yield return null;
        }

        controller.IsGeneratingImage = false;

        if (!string.IsNullOrWhiteSpace(error))
        {
            controller.GenerationError = error;
            BuildCurrentStep();
            yield break;
        }

        var savedPath = SaveGeneratedSprite(option, generated);
        controller.LastGeneratedPath = savedPath;

        var generatedOption = new AppearanceOptionDefinition
        {
            id = $"generated_{definition.category}_{DateTime.UtcNow:HHmmssfff}",
            label = "Generated",
            slotCategory = option.slotCategory,
            slotLabel = option.slotLabel,
            slotCategorySecondary = option.slotCategorySecondary,
            slotLabelSecondary = option.slotLabelSecondary,
            runtimeSprite = Sprite.Create(generated, new Rect(0f, 0f, generated.width, generated.height), new Vector2(0.5f, 0.5f), 100f)
        };

        controller.AddGeneratedOption(definition.category, generatedOption);
        ApplyGeneratedSprite(generatedOption, generated);
        BuildCurrentStep();
    }

    private string BuildReplicatePrompt(AppearanceCategoryDefinition definition, AppearanceOptionDefinition option)
    {
        var race = controller.SelectedRace != null ? controller.SelectedRace.name : "Human";
        var gender = controller.SelectedGender.HasValue ? controller.SelectedGender.Value.ToString() : "Any";
        var slot = !string.IsNullOrWhiteSpace(option.slotCategory) ? option.slotCategory : definition.category.ToString();
        var label = option.label ?? "variant";

        return $"Generate a 2D character part sprite for Unity 2D rig. " +
               $"Category: {slot}. Variant: {label}. Race: {race}. Gender: {gender}. " +
               $"Transparent background PNG. Canvas size 512x512. Centered pivot aligned to torso anchor. " +
               $"Flat colors, clean outlines, no painterly noise. Match existing style.";
    }

    private string SaveGeneratedSprite(AppearanceOptionDefinition option, Texture2D texture)
    {
        var category = !string.IsNullOrWhiteSpace(option.slotCategory) ? option.slotCategory : "Unsorted";
        var label = !string.IsNullOrWhiteSpace(option.slotLabel) ? option.slotLabel : option.label ?? "generated";
        var fileName = $"{label}_{DateTime.UtcNow:yyyyMMdd_HHmmss}.png".ToLowerInvariant();

        var dir = Path.Combine(Application.persistentDataPath, generatedOutputFolder, category);
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, fileName);

        var png = texture.EncodeToPNG();
        File.WriteAllBytes(path, png);

        var lastPathFile = Path.Combine(Application.persistentDataPath, generatedOutputFolder, "last_generated.txt");
        File.WriteAllText(lastPathFile, path);

        return path;
    }

    private void ApplyGeneratedSprite(AppearanceOptionDefinition option, Texture2D texture)
    {
        if (previewRigInstance == null || texture == null)
        {
            return;
        }

        var sprite = Sprite.Create(texture, new Rect(0f, 0f, texture.width, texture.height), new Vector2(0.5f, 0.5f), 100f);
        if (option != null)
        {
            option.runtimeSprite = sprite;
        }
        ApplySpriteToCategory(option.slotCategory, sprite);
        if (!string.IsNullOrWhiteSpace(option.slotCategorySecondary))
        {
            ApplySpriteToCategory(option.slotCategorySecondary, sprite);
        }
    }

    private void ApplySpriteToCategory(string category, Sprite sprite)
    {
        if (string.IsNullOrWhiteSpace(category))
        {
            return;
        }

        var resolvers = previewRigInstance.GetComponentsInChildren<UnityEngine.U2D.Animation.SpriteResolver>(true);
        foreach (var resolver in resolvers)
        {
            if (resolver == null)
            {
                continue;
            }

            var resolverCategory = resolver.GetCategory();
            if (string.IsNullOrWhiteSpace(resolverCategory))
            {
                resolverCategory = resolver.gameObject.name;
                if (!string.IsNullOrWhiteSpace(resolverCategory))
                {
                    resolver.SetCategoryAndLabel(resolverCategory, "placeholder");
                }
            }

            if (resolverCategory == category)
            {
                var renderer = resolver.GetComponent<SpriteRenderer>();
                if (renderer != null)
                {
                    resolver.enabled = false;
                    renderer.sprite = sprite;
                }
            }
        }
    }

    private void ClearPanel()
    {
        if (panelRoot != null)
        {
            Destroy(panelRoot.gameObject);
        }
        panelRoot = null;

        if (canvas != null)
        {
            var existingPanels = canvas.GetComponentsInChildren<RectTransform>(true);
            foreach (var rect in existingPanels)
            {
                if (rect != null && rect.name == "CharacterCreationPanel")
                {
                    Destroy(rect.gameObject);
                }
            }
        }

        if (previewRigInstance != null)
        {
            Destroy(previewRigInstance);
            previewRigInstance = null;
        }

        if (previewCamera != null)
        {
            Destroy(previewCamera.gameObject);
            previewCamera = null;
        }

        if (previewTexture != null)
        {
            previewTexture.Release();
            Destroy(previewTexture);
            previewTexture = null;
        }

        previewImage = null;
    }

    private RectTransform CreatePanel(Transform parent)
    {
        var panelObject = new GameObject("CharacterCreationPanel");
        panelObject.transform.SetParent(parent, false);
        panelObject.transform.SetAsLastSibling();

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

        var layout = contentObject.AddComponent<VerticalLayoutGroup>();
        layout.spacing = 10f;
        layout.childControlHeight = true;
        layout.childControlWidth = true;
        layout.childForceExpandHeight = false;
        layout.childForceExpandWidth = false;

        return rect;
    }

    private RectTransform CreateHorizontalGroup(Transform parent, float preferredHeight = 36f, TextAnchor alignment = TextAnchor.MiddleLeft)
    {
        var rowObject = new GameObject("Row");
        rowObject.transform.SetParent(parent, false);
        var rect = rowObject.AddComponent<RectTransform>();
        rect.anchorMin = new Vector2(0f, 0f);
        rect.anchorMax = new Vector2(1f, 0f);
        rect.sizeDelta = new Vector2(0f, preferredHeight);

        var layout = rowObject.AddComponent<HorizontalLayoutGroup>();
        layout.spacing = 8f;
        layout.childControlHeight = true;
        layout.childControlWidth = true;
        layout.childForceExpandHeight = false;
        layout.childForceExpandWidth = false;
        layout.childAlignment = alignment;

        var layoutElement = rowObject.AddComponent<LayoutElement>();
        layoutElement.preferredHeight = preferredHeight;

        return rect;
    }

    private RectTransform CreateVerticalGroup(Transform parent, float preferredHeight = 0f, float preferredWidth = 0f, TextAnchor alignment = TextAnchor.UpperLeft)
    {
        var columnObject = new GameObject("Column");
        columnObject.transform.SetParent(parent, false);
        var rect = columnObject.AddComponent<RectTransform>();
        rect.anchorMin = new Vector2(0f, 0f);
        rect.anchorMax = new Vector2(1f, 1f);
        rect.sizeDelta = Vector2.zero;

        var layout = columnObject.AddComponent<VerticalLayoutGroup>();
        layout.spacing = 8f;
        layout.childControlHeight = true;
        layout.childControlWidth = true;
        layout.childForceExpandHeight = false;
        layout.childForceExpandWidth = false;
        layout.childAlignment = alignment;

        var layoutElement = columnObject.AddComponent<LayoutElement>();
        if (preferredHeight > 0f)
        {
            layoutElement.preferredHeight = preferredHeight;
        }
        if (preferredWidth > 0f)
        {
            layoutElement.preferredWidth = preferredWidth;
        }

        return rect;
    }

    private TMP_Text CreateHeader(Transform parent, string text, int fontSize = 44)
    {
        var title = MenuStyling.CreateBookTitle(parent, text, new Vector2(0f, 72f), "Header");
        if (title != null)
        {
            title.fontSize = fontSize;
            if (titleFont != null)
            {
                title.font = titleFont;
                title.fontSharedMaterial = titleFont.material;
                title.ForceMeshUpdate();
            }
        }
        return title;
    }

    private TMP_Text CreateText(Transform parent, string text)
    {
        return CreateText(parent, text, 18, TextAlignmentOptions.MidlineLeft, 28f);
    }

    private TMP_Text CreateText(Transform parent, string text, int fontSize, TextAlignmentOptions alignment, float preferredHeight)
    {
        return CreateText(parent, text, fontSize, alignment, preferredHeight, FontStyles.Normal);
    }

    private TMP_Text CreateText(Transform parent, string text, int fontSize, TextAlignmentOptions alignment, float preferredHeight, FontStyles style, float preferredWidth = 0f)
    {
        var textObject = new GameObject("Text");
        textObject.transform.SetParent(parent, false);
        var uiText = textObject.AddComponent<TextMeshProUGUI>();
        uiText.text = text;
        uiText.font = resolvedFont;
        uiText.fontSize = fontSize;
        uiText.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : UnityColor.black;
        uiText.alignment = alignment;
        uiText.fontStyle = style;

        var layout = textObject.AddComponent<LayoutElement>();
        layout.preferredHeight = preferredHeight;
        if (preferredWidth > 0f)
        {
            layout.preferredWidth = preferredWidth;
        }

        return uiText;
    }

    private void CreateSpacer(Transform parent, float height)
    {
        var spacer = new GameObject("Spacer");
        spacer.transform.SetParent(parent, false);
        var layout = spacer.AddComponent<LayoutElement>();
        layout.preferredHeight = height;
        layout.minHeight = height;
    }

    private void CreateFlexibleSpacer(Transform parent)
    {
        var spacer = new GameObject("FlexibleSpacer");
        spacer.transform.SetParent(parent, false);
        var layout = spacer.AddComponent<LayoutElement>();
        layout.flexibleWidth = 1f;
        layout.minWidth = 0f;
        layout.preferredWidth = 0f;
    }

    private void CenterTitle(TMP_Text title)
    {
        if (title == null)
        {
            return;
        }

        title.alignment = TextAlignmentOptions.Center;
        var rect = title.GetComponent<RectTransform>();
        if (rect != null)
        {
            rect.anchorMin = new Vector2(0f, 1f);
            rect.anchorMax = new Vector2(1f, 1f);
            rect.pivot = new Vector2(0.5f, 1f);
            rect.sizeDelta = new Vector2(0f, rect.sizeDelta.y);
        }

        var layout = title.GetComponent<LayoutElement>();
        if (layout != null)
        {
            layout.preferredWidth = 0f;
            layout.minWidth = 0f;
            layout.flexibleWidth = 1f;
        }
    }

    private void CenterText(TMP_Text text)
    {
        if (text == null)
        {
            return;
        }

        text.alignment = TextAlignmentOptions.Center;
        var rect = text.GetComponent<RectTransform>();
        if (rect != null)
        {
            rect.anchorMin = new Vector2(0f, 1f);
            rect.anchorMax = new Vector2(1f, 1f);
            rect.pivot = new Vector2(0.5f, 1f);
            rect.sizeDelta = new Vector2(0f, rect.sizeDelta.y);
        }

        var layout = text.GetComponent<LayoutElement>();
        if (layout != null)
        {
            layout.preferredWidth = 0f;
            layout.minWidth = 0f;
            layout.flexibleWidth = 1f;
        }
    }

    private void CreateClassPreview(Transform parent, float size, bool fillHalfWidth)
    {
        var previewObject = new GameObject("ClassPreview");
        previewObject.transform.SetParent(parent, false);
        var rect = previewObject.AddComponent<RectTransform>();
        rect.anchorMin = new Vector2(0f, 0f);
        rect.anchorMax = new Vector2(0f, 1f);
        rect.sizeDelta = new Vector2(size, size);

        var image = previewObject.AddComponent<Image>();
        image.color = new UnityColor(0.96f, 0.94f, 0.9f, 1f);

        var layoutElement = previewObject.AddComponent<LayoutElement>();
        layoutElement.preferredWidth = size;
        layoutElement.preferredHeight = size;
        layoutElement.flexibleWidth = fillHalfWidth ? 1f : 0f;
        layoutElement.flexibleHeight = 0f;

        if (controller.SelectedClass != null && !string.IsNullOrWhiteSpace(controller.SelectedClass.image))
        {
            var sprite = Resources.Load<Sprite>($"Main/{controller.SelectedClass.image}");
            if (sprite != null)
            {
                image.sprite = sprite;
                image.preserveAspect = true;
                image.color = UnityColor.white;
            }
        }
    }

    private void CreateRacePreview(Transform parent, float size, bool fillHalfWidth)
    {
        var previewObject = new GameObject("RacePreview");
        previewObject.transform.SetParent(parent, false);
        var rect = previewObject.AddComponent<RectTransform>();
        rect.anchorMin = new Vector2(0f, 0f);
        rect.anchorMax = new Vector2(0f, 1f);
        rect.sizeDelta = new Vector2(size, size);

        var image = previewObject.AddComponent<Image>();
        image.color = new UnityColor(0.96f, 0.94f, 0.9f, 1f);

        var layoutElement = previewObject.AddComponent<LayoutElement>();
        layoutElement.preferredWidth = size;
        layoutElement.preferredHeight = size;
        layoutElement.flexibleWidth = fillHalfWidth ? 1f : 0f;
        layoutElement.flexibleHeight = 0f;

        if (controller.SelectedRace != null && !string.IsNullOrWhiteSpace(controller.SelectedRace.image))
        {
            var sprite = Resources.Load<Sprite>($"Main/{controller.SelectedRace.image}");
            if (sprite != null)
            {
                image.sprite = sprite;
                image.preserveAspect = true;
                image.color = UnityColor.white;
            }
        }
    }

    private Button CreateButton(Transform parent, string label, UnityEngine.Events.UnityAction onClick, bool isSelected, float preferredWidth = 0f, bool interactable = true, UnityColor? textColorOverride = null, bool useBackgroundImage = true, bool useResourceSprite = true, float height = 44f)
    {
        var size = new Vector2(preferredWidth > 0f ? preferredWidth : 280f, height);
        var button = MenuStyling.CreateBookButton(parent, label, size, $"Button_{label}");
        var rect = button.GetComponent<RectTransform>();
        if (rect != null)
        {
            rect.sizeDelta = new Vector2(rect.sizeDelta.x, height);
        }
        var layoutElement = button.GetComponent<LayoutElement>();
        if (layoutElement != null)
        {
            layoutElement.preferredHeight = height;
            layoutElement.minHeight = height;
        }
        button.onClick.AddListener(onClick);
        button.interactable = interactable;

        if (!useBackgroundImage)
        {
            button.image.sprite = null;
            button.image.color = new UnityColor(0f, 0f, 0f, 0f);
        }
        else
        {
            var resourceSprite = useResourceSprite ? MenuStyling.GetResourceButtonSprite() : null;
            var resourceSelectedSprite = useResourceSprite ? MenuStyling.GetResourceButtonSelectedSprite() : null;
            var normalSprite = resourceSprite != null ? resourceSprite : MenuStyling.GetRoundedButtonSprite();
            var selectedSprite = resourceSelectedSprite != null ? resourceSelectedSprite : MenuStyling.GetRoundedSelectedSprite();
            button.image.sprite = isSelected ? selectedSprite : normalSprite;
            button.image.type = useResourceSprite && resourceSprite != null ? Image.Type.Simple : Image.Type.Sliced;
        }

        if (!interactable)
        {
            button.image.color = buttonDisabledColor;
        }

        if (textColorOverride.HasValue)
        {
            var text = button.GetComponentInChildren<TextMeshProUGUI>();
            if (text != null)
            {
                text.color = textColorOverride.Value;
            }
        }

        return button;
    }

    private void ExitToMainMenu()
    {
        var startScreen = StartScreenController.GetOrCreate();
        startScreen.gameObject.SetActive(true);
        startScreen.Activate();
        startScreen.ShowMainMenu();
        Deactivate();
    }

    private TMP_InputField CreateInputField(Transform parent, string label, string value, bool multiline, Action<string> onChanged, float preferredWidth = 0f, float preferredHeight = 0f, TextAlignmentOptions labelAlignment = TextAlignmentOptions.MidlineLeft)
    {
        CreateText(parent, label, 18, labelAlignment, 24f, FontStyles.Bold);

        var fieldObject = new GameObject($"{label}_Input");
        fieldObject.transform.SetParent(parent, false);
        var fieldRect = fieldObject.AddComponent<RectTransform>();
        if (preferredWidth > 0f)
        {
            fieldRect.anchorMin = new Vector2(0f, 1f);
            fieldRect.anchorMax = new Vector2(0f, 1f);
            fieldRect.pivot = new Vector2(0f, 1f);
            fieldRect.sizeDelta = new Vector2(preferredWidth, 0f);
        }

        var image = fieldObject.AddComponent<Image>();
        image.color = MenuStyling.Theme != null ? MenuStyling.Theme.parchmentDark : UnityColor.white;

        var inputField = fieldObject.AddComponent<TMP_InputField>();
        inputField.lineType = multiline ? TMP_InputField.LineType.MultiLineNewline : TMP_InputField.LineType.SingleLine;
        inputField.text = value;

        var textArea = new GameObject("Text Area");
        textArea.transform.SetParent(fieldObject.transform, false);
        var textAreaRect = textArea.AddComponent<RectTransform>();
        textAreaRect.anchorMin = Vector2.zero;
        textAreaRect.anchorMax = Vector2.one;
        textAreaRect.offsetMin = new Vector2(8f, 6f);
        textAreaRect.offsetMax = new Vector2(-8f, -6f);
        textArea.AddComponent<RectMask2D>();

        var textObject = new GameObject("Text");
        textObject.transform.SetParent(textArea.transform, false);
        var text = textObject.AddComponent<TextMeshProUGUI>();
        text.font = resolvedFont;
        text.fontSize = 16;
        text.alignment = multiline ? TextAlignmentOptions.TopLeft : TextAlignmentOptions.MidlineLeft;
        text.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : UnityColor.black;

        var placeholderObject = new GameObject("Placeholder");
        placeholderObject.transform.SetParent(textArea.transform, false);
        var placeholder = placeholderObject.AddComponent<TextMeshProUGUI>();
        placeholder.text = "Enter text...";
        placeholder.font = resolvedFont;
        placeholder.fontSize = 16;
        placeholder.fontStyle = FontStyles.Italic;
        placeholder.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkMuted : new UnityColor(0.4f, 0.4f, 0.4f, 1f);
        placeholder.alignment = multiline ? TextAlignmentOptions.TopLeft : TextAlignmentOptions.MidlineLeft;

        StretchToFill(textObject.GetComponent<RectTransform>());
        StretchToFill(placeholderObject.GetComponent<RectTransform>());

        inputField.textComponent = text;
        inputField.placeholder = placeholder;
        inputField.targetGraphic = image;
        inputField.onValueChanged.AddListener(valueChanged => onChanged?.Invoke(valueChanged));

        var layout = fieldObject.AddComponent<LayoutElement>();
        if (preferredHeight <= 0f)
        {
            preferredHeight = multiline ? 140f : 36f;
        }
        layout.preferredHeight = preferredHeight;
        if (preferredWidth > 0f)
        {
            layout.preferredWidth = preferredWidth;
            layout.minWidth = preferredWidth;
            layout.flexibleWidth = 0f;
        }

        return inputField;
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

    private void StretchToFill(RectTransform rectTransform)
    {
        rectTransform.anchorMin = Vector2.zero;
        rectTransform.anchorMax = Vector2.one;
        rectTransform.offsetMin = Vector2.zero;
        rectTransform.offsetMax = Vector2.zero;
    }

    private TMP_FontAsset ResolveFont()
    {
        if (fallbackFont != null)
        {
            return fallbackFont;
        }

        var defaultFont = TMP_Settings.defaultFontAsset;
        if (defaultFont != null)
        {
            return defaultFont;
        }

        var resourcesFont = Resources.Load<TMP_FontAsset>("LiberationSans SDF");
        if (resourcesFont != null)
        {
            return resourcesFont;
        }

        var anyFonts = Resources.FindObjectsOfTypeAll<TMP_FontAsset>();
        if (anyFonts != null && anyFonts.Length > 0)
        {
            return anyFonts[0];
        }

        var builtinArial = Resources.GetBuiltinResource<Font>("Arial.ttf");
        if (builtinArial != null)
        {
            return TMP_FontAsset.CreateFontAsset(builtinArial);
        }

        Debug.LogWarning("CharacterCreationBootstrap: Unable to resolve a TMP font asset.");
        return null;
    }

    private TMP_FontAsset ResolveTitleFont()
    {
        if (titleFontOverride != null)
        {
            return titleFontOverride;
        }

        if (fallbackFont != null)
        {
            return fallbackFont;
        }

        var fontAsset = MenuStyling.GetTitleFontAsset();
        if (fontAsset != null)
        {
            return fontAsset;
        }

        const string fontPath = "Fonts/TT Ramillas Initials Trial Regular";
        var tmpFont = Resources.Load<TMP_FontAsset>(fontPath);
        if (tmpFont != null)
        {
            return tmpFont;
        }

        var font = Resources.Load<Font>(fontPath);
        if (font != null)
        {
            return TMP_FontAsset.CreateFontAsset(font);
        }

        Debug.LogWarning($"CharacterCreationBootstrap: Unable to load title font at {fontPath}.");
        return null;
    }
}
