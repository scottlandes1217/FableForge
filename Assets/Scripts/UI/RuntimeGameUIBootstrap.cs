using System;
using System.Collections.Generic;
using System.IO;
using FableForge.Models;
using FableForge.Systems;
using TMPro;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.U2D.Animation;
using UnityEngine.UI;

namespace FableForge.UI
{
    public class RuntimeGameUIBootstrap : MonoBehaviour
    {
        private const float ButtonWidth = 280f;
        private const float ButtonHeight = 80f;
        private const float ButtonSpacing = 24f;
        private const float StackSpacing = 20f;
        private const float StatusPanelWidth = 720f;
        private const float NameplateHeight = 220f;
        private const float StatusBarWidth = 575f;
        private const float PartyHudStatusBarWidth = 296f;
        private const float ActionBarPanelWidth = 980f;
        private const float ActionBarContentPaddingH = 56f;
        private const float ActionBarSlotSpacing = 8f;
        private const int ActionBarSlotCount = 10;
        private static readonly float ActionBarSlotWidth = (ActionBarPanelWidth - ActionBarContentPaddingH - (ActionBarSlotCount - 1) * ActionBarSlotSpacing) / ActionBarSlotCount;
        private const float ActionBarContentPaddingV = 16f;
        private static readonly float ActionBarPanelHeightSingleRow = ActionBarSlotWidth + ActionBarContentPaddingV;
        private const float StatusBarHeight = 31f;
        private const float ExperienceBarHeight = 8f;
        private const float StatusBarSpacing = 10f;
        private const float NameplatePaddingX = 36f;
        private const float NameplatePaddingTop = 18f;
        private const float NameplatePaddingBottom = 18f;
        private const float NameplateTitleHeight = 28f;
        private const float NameplateTitleSpacing = 8f;
        private const float NameplateContentOffsetY = 12f;
        private const float NameplateBarsOffsetY = 18f;
        private static readonly Vector2 StatusPanelMargin = new Vector2(12f, -115f);
        private const int MaxSaveSlotsPerCharacter = 5;
        private const string CharacterKeyPrefix = "FableForge_Character_";
        private static readonly Vector2 TopRightMargin = new Vector2(-16f, -16f);
        private static readonly Vector2 BottomRightMargin = new Vector2(-16f, 16f);
        private static readonly Vector2 SettingsPanelOffset = Vector2.zero;

        private GameObject combinedPanel;
        private GameObject combinedInventoryTab;
        private GameObject combinedSkillsTab;
        private GameObject combinedAttributesTab;
        private GameObject combinedBuildTab;
        private GameObject combinedCompanionsTab;
        private Button combinedInventoryTabButton;
        private Button combinedSkillsTabButton;
        private Button combinedAttributesTabButton;
        private Button combinedBuildTabButton;
        private Button combinedCompanionsTabButton;
        private TextMeshProUGUI attributePointsLabel;
        private readonly Dictionary<Ability, TextMeshProUGUI> attributeValueLabels = new Dictionary<Ability, TextMeshProUGUI>();
        private readonly Dictionary<Ability, Button> attributeMinusButtons = new Dictionary<Ability, Button>();
        private readonly Dictionary<Ability, Button> attributePlusButtons = new Dictionary<Ability, Button>();
        private Button attributeSaveButton;
        private Button attributeResetButton;
        private readonly Dictionary<Ability, int> pendingAttributeAllocations = new Dictionary<Ability, int>();
        private int pendingAttributePoints;
        private Canvas rootCanvas;
        private readonly Dictionary<string, ItemDefinition> itemDefinitions = new Dictionary<string, ItemDefinition>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, SkillDefinition> skillDefinitions = new Dictionary<string, SkillDefinition>(StringComparer.OrdinalIgnoreCase);
        private Transform partyHudRoot;
        private Transform partyCompanionRoot;
        private readonly Dictionary<string, BattleActorStatus> partyHudActorStatus = new Dictionary<string, BattleActorStatus>(StringComparer.OrdinalIgnoreCase);
        private readonly List<Button> inventoryFilterButtons = new List<Button>();
        private readonly List<GameObject> inventoryFilterPanels = new List<GameObject>();
        private readonly List<Button> buildTypeButtons = new List<Button>();
        private readonly List<GameObject> buildTypePanels = new List<GameObject>();
        private string currentInventoryFilter = "All";
        private string currentBuildType = null;
        private GameObject settingsPanel;
        private RectTransform settingsContentRoot;
        private GameObject chestPanel;
        private RectTransform chestItemsRoot;
        private TextMeshProUGUI chestTitle;
        private Button chestTakeAllButton;
        private ChestInstance activeChest;
        private GameObject companionPanel;
        private TextMeshProUGUI companionTitle;
        private TextMeshProUGUI companionBody;
        private Button companionBefriendButton;
        private Button companionCloseButton;
        private CompanionInstance activeCompanion;
        private GameObject battlePanel;
        private Transform battleLeftRoot;
        private Transform battleRightRoot;
        private Transform battleActionsRoot;
        private EnemyInstance activeEnemy;
        private TextMeshProUGUI battlePlayerEntry;
        private int battlePlayerHp;
        private int battleEnemyStunTurns;
        private int battleEnemyAttackModifier;
        private int battleEnemyAttackDebuffTurns;
        private int battleEnemyBurnDamage;
        private int battleEnemyBurnTurns;
        private EnemyInstance battleTargetEnemy;
        private Button battleEnemyButton;
        private readonly List<EnemyInstance> activeEnemies = new List<EnemyInstance>();
        private readonly Dictionary<EnemyInstance, BattleEnemyStatus> battleEnemyStatus = new Dictionary<EnemyInstance, BattleEnemyStatus>();
        private readonly List<BattleActor> battlePartyActors = new List<BattleActor>();
        private readonly Dictionary<string, BattleActorStatus> battleActorStatus = new Dictionary<string, BattleActorStatus>(StringComparer.OrdinalIgnoreCase);
        private readonly HashSet<string> battleActorsActed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private BattleActor selectedBattleActor;
        private readonly Dictionary<string, CompanionSkillDefinition> companionSkillDefinitions = new Dictionary<string, CompanionSkillDefinition>(StringComparer.OrdinalIgnoreCase);
        private GameObject itemActionPanel;
        private TextMeshProUGUI itemActionTitle;
        private Button itemUseButton;
        private Button itemEquipButton;
        private Button itemDropButton;
        private Item selectedItem;
        private ItemDefinition selectedItemDefinition;
        private readonly Dictionary<string, Transform> equipmentSlotRoots = new Dictionary<string, Transform>(StringComparer.OrdinalIgnoreCase);
        private Transform companionsListRoot;
        private GameObject actionBarPanel;
        private RectTransform actionBarContent;
        private GridLayoutGroup actionBarGrid;
        private bool actionBarExpanded;
        private readonly Dictionary<string, List<BattleAction>> actionBarAssignments = new Dictionary<string, List<BattleAction>>(StringComparer.OrdinalIgnoreCase);

        private enum SettingsView
        {
            Main,
            SaveSlots,
            LoadSlots
        }

        private enum CombinedTab
        {
            Inventory,
            Skills,
            Attributes,
            Build,
            Companions
        }

        private SettingsView settingsView = SettingsView.Main;
        private CombinedTab combinedTab = CombinedTab.Inventory;
        private float nextCombinedRefreshTime;
        private float nextActionBarRefreshTime;

        private Font defaultFont;
        private Image healthFill;
        private Image resourceFill;
        private Image experienceFill;
        private TextMeshProUGUI nameplateTitle;
        private TextMeshProUGUI healthLabel;
        private TextMeshProUGUI resourceLabel;
        private GameObject resourceBarRoot;
        private static Sprite cachedSolidSprite;
        private float nextStatusRefreshTime;
        private CharacterCreationData characterCreationData;

        private static Sprite GetButtonIconSprite(string label)
        {
            switch (label)
            {
                case "Settings":
                    return Resources.Load<Sprite>("Main/settings_icon");
                case "Inventory":
                    return Resources.Load<Sprite>("Main/inventory_icon");
                case "Character":
                    return Resources.Load<Sprite>("Main/charactersheet_icon");
                case "Build":
                    return Resources.Load<Sprite>("Main/builder_icon");
                default:
                    return null;
            }
        }

        private static Sprite GetSolidSprite()
        {
            if (cachedSolidSprite != null)
            {
                return cachedSolidSprite;
            }

            var texture = Texture2D.whiteTexture;
            cachedSolidSprite = Sprite.Create(texture, new Rect(0f, 0f, texture.width, texture.height), new Vector2(0.5f, 0.5f), 1f);
            return cachedSolidSprite;
        }

        private static Sprite LoadStatusBarBackgroundSprite()
        {
            var sprite = Resources.Load<Sprite>("Main/health_container");
            if (sprite != null)
            {
                return sprite;
            }

            var sprites = Resources.LoadAll<Sprite>("Main/health_container");
            if (sprites != null && sprites.Length > 0)
            {
                return sprites[0];
            }

            return null;
        }

        private void CreateStatusHUD(Transform parent)
        {
            var hudObject = new GameObject("StatusHUD");
            hudObject.transform.SetParent(parent, false);
            var rect = hudObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0f, 1f);
            rect.anchorMax = new Vector2(0f, 1f);
            rect.pivot = new Vector2(0f, 1f);
            rect.anchoredPosition = StatusPanelMargin;
            rect.sizeDelta = new Vector2(StatusPanelWidth, 0f);

            CreateNameplate(hudObject.transform);
        }

        private void CreatePartyHud(Transform parent)
        {
            var rootObject = new GameObject("PartyHud");
            rootObject.transform.SetParent(parent, false);
            var rect = rootObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0f, 1f);
            rect.anchorMax = new Vector2(0f, 1f);
            rect.pivot = new Vector2(0f, 1f);
            rect.anchoredPosition = new Vector2(16f, -16f);
            rect.sizeDelta = new Vector2(340f, 0f);

            var layout = rootObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 10f;
            layout.childAlignment = TextAnchor.UpperLeft;
            layout.childControlWidth = false;
            layout.childControlHeight = false;
            layout.childForceExpandWidth = false;
            layout.childForceExpandHeight = false;
            partyHudRoot = rootObject.transform;

            var playerPlate = CreatePartyHudPlayerPlate(rootObject.transform);

            var companionRootObj = new GameObject("CompanionPlates");
            var companionRect = companionRootObj.AddComponent<RectTransform>();
            var companionImage = companionRootObj.AddComponent<Image>();
            companionImage.color = new Color(1f, 1f, 1f, 0f);
            companionImage.raycastTarget = false;
            var companionFitter = companionRootObj.AddComponent<ContentSizeFitter>();
            companionFitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            companionFitter.horizontalFit = ContentSizeFitter.FitMode.Unconstrained;
            var companionLayout = companionRootObj.AddComponent<VerticalLayoutGroup>();
            companionLayout.spacing = 6f;
            companionLayout.childAlignment = TextAnchor.UpperLeft;
            companionLayout.childControlWidth = false;
            companionLayout.childControlHeight = false;
            companionLayout.childForceExpandWidth = false;
            companionLayout.childForceExpandHeight = false;

            partyCompanionRoot = companionRect;
            partyCompanionRoot.SetParent(rootObject.transform, false);

            playerPlate.SetAsFirstSibling();
            partyCompanionRoot.SetSiblingIndex(1);

            var fitter = rootObject.AddComponent<ContentSizeFitter>();
            fitter.horizontalFit = ContentSizeFitter.FitMode.Unconstrained;
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
        }

        private Transform CreatePartyHudPlayerPlate(Transform parent)
        {
            var plateObject = new GameObject("PlayerPlate");
            plateObject.transform.SetParent(parent, false);
            var rect = plateObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(320f, 84f);

            var image = plateObject.AddComponent<Image>();
            image.sprite = MenuStyling.GetRoundedButtonSprite();
            image.type = Image.Type.Sliced;
            image.color = new Color(0.2f, 0.25f, 0.35f, 0.75f);

            var button = plateObject.AddComponent<Button>();
            button.onClick.AddListener(() => SelectBattleActorByKey("player"));

            var titleObject = new GameObject("Name");
            titleObject.transform.SetParent(plateObject.transform, false);
            var titleRect = titleObject.AddComponent<RectTransform>();
            titleRect.anchorMin = new Vector2(0f, 1f);
            titleRect.anchorMax = new Vector2(1f, 1f);
            titleRect.pivot = new Vector2(0.5f, 1f);
            titleRect.anchoredPosition = new Vector2(0f, -6f);
            titleRect.sizeDelta = new Vector2(-16f, 24f);

            nameplateTitle = titleObject.AddComponent<TextMeshProUGUI>();
            nameplateTitle.fontSize = 18f;
            nameplateTitle.alignment = TextAlignmentOptions.Left;
            nameplateTitle.color = Color.white;

            var barsObject = new GameObject("Bars");
            barsObject.transform.SetParent(plateObject.transform, false);
            var barsRect = barsObject.AddComponent<RectTransform>();
            barsRect.anchorMin = new Vector2(0f, 0f);
            barsRect.anchorMax = new Vector2(1f, 1f);
            barsRect.offsetMin = new Vector2(12f, 8f);
            barsRect.offsetMax = new Vector2(-12f, -32f);

            var barsLayout = barsObject.AddComponent<VerticalLayoutGroup>();
            barsLayout.spacing = 6f;
            barsLayout.childAlignment = TextAnchor.UpperLeft;
            barsLayout.childControlWidth = false;
            barsLayout.childControlHeight = false;
            barsLayout.childForceExpandWidth = false;
            barsLayout.childForceExpandHeight = false;

            CreateStatusBars(barsObject.transform, PartyHudStatusBarWidth);

            partyHudActorStatus["player"] = new BattleActorStatus
            {
                actor = new BattleActor { key = "player", kind = BattleActorKind.Player, name = "Player" },
                button = button,
                background = image,
                label = nameplateTitle,
                hpFill = healthFill,
                resourceFill = resourceFill
            };
            return plateObject.transform;
        }

        private void RefreshPartyHud()
        {
            if (partyCompanionRoot == null)
            {
                return;
            }

            var keysToRemove = new List<string>();
            foreach (var key in partyHudActorStatus.Keys)
            {
                if (!string.Equals(key, "player", StringComparison.OrdinalIgnoreCase))
                {
                    keysToRemove.Add(key);
                }
            }
            for (var i = 0; i < keysToRemove.Count; i++)
            {
                partyHudActorStatus.Remove(keysToRemove[i]);
            }

            for (var i = partyCompanionRoot.childCount - 1; i >= 0; i--)
            {
                Destroy(partyCompanionRoot.GetChild(i).gameObject);
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || player.companions == null)
            {
                return;
            }

            var index = 0;
            foreach (var companion in player.companions)
            {
                if (companion == null)
                {
                    continue;
                }

                var key = $"companion_{index}_{companion.id}";
                CreatePartyHudCompanionPlate(partyCompanionRoot, companion, key);
                index++;
            }
        }

        private Transform CreatePartyHudCompanionPlate(Transform parent, Animal companion, string key)
        {
            var plateObject = new GameObject($"{companion.id}_Plate");
            plateObject.transform.SetParent(parent, false);
            var rect = plateObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(320f, 60f);

            var image = plateObject.AddComponent<Image>();
            image.sprite = MenuStyling.GetRoundedButtonSprite();
            image.type = Image.Type.Sliced;
            image.color = new Color(0.2f, 0.25f, 0.35f, 0.6f);

            var button = plateObject.AddComponent<Button>();
            button.onClick.AddListener(() => SelectBattleActorByKey(key));

            var nameObject = new GameObject("Name");
            nameObject.transform.SetParent(plateObject.transform, false);
            var nameRect = nameObject.AddComponent<RectTransform>();
            nameRect.anchorMin = new Vector2(0f, 1f);
            nameRect.anchorMax = new Vector2(1f, 1f);
            nameRect.pivot = new Vector2(0.5f, 1f);
            nameRect.anchoredPosition = new Vector2(0f, -6f);
            nameRect.sizeDelta = new Vector2(-16f, 20f);

            var nameText = nameObject.AddComponent<TextMeshProUGUI>();
            nameText.text = !string.IsNullOrWhiteSpace(companion.name) ? companion.name : companion.id;
            nameText.fontSize = 16f;
            nameText.alignment = TextAlignmentOptions.Left;
            nameText.color = Color.white;

            var hpBar = CreateInlineBar(plateObject.transform, new Vector2(296f, 10f), new Color(0.2f, 0.85f, 0.2f, 1f), out _);
            hpBar.transform.localPosition = new Vector3(0f, -18f, 0f);
            var maxHp = GetCompanionMaxHp(companion.id);
            hpBar.fillAmount = maxHp > 0 ? 1f : 0f;

            if (!string.IsNullOrWhiteSpace(key))
            {
                partyHudActorStatus[key] = new BattleActorStatus
                {
                    actor = new BattleActor { key = key, kind = BattleActorKind.Companion, name = companion.name },
                    button = button,
                    background = image,
                    label = nameText,
                    hpFill = hpBar
                };
            }
            return plateObject.transform;
        }

        private void CreateNameplate(Transform parent)
        {
            var plateObject = new GameObject("Nameplate");
            plateObject.transform.SetParent(parent, false);
            var rect = plateObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(StatusPanelWidth, NameplateHeight);

            var layout = plateObject.AddComponent<LayoutElement>();
            layout.preferredWidth = StatusPanelWidth;
            layout.preferredHeight = NameplateHeight;

            var image = plateObject.AddComponent<Image>();
            var plateSprite = Resources.Load<Sprite>("Main/health_container");
            if (plateSprite == null)
            {
                var sliced = Resources.LoadAll<Sprite>("Main/health_container");
                plateSprite = sliced != null && sliced.Length > 0 ? sliced[0] : null;
            }
            image.sprite = plateSprite != null ? plateSprite : MenuStyling.GetRoundedButtonSprite();
            image.type = plateSprite != null ? Image.Type.Simple : Image.Type.Sliced;
            image.color = Color.white;

            var titleObject = new GameObject("NameplateTitle");
            titleObject.transform.SetParent(plateObject.transform, false);
            var titleRect = titleObject.AddComponent<RectTransform>();
            titleRect.anchorMin = new Vector2(0f, 1f);
            titleRect.anchorMax = new Vector2(1f, 1f);
            titleRect.pivot = new Vector2(0.5f, 1f);
            titleRect.anchoredPosition = new Vector2(0f, -(NameplatePaddingTop + NameplateContentOffsetY));
            titleRect.sizeDelta = new Vector2(-NameplatePaddingX * 2f, NameplateTitleHeight);

            nameplateTitle = titleObject.AddComponent<TextMeshProUGUI>();
            nameplateTitle.text = FormatNameplateTitle(1);
            nameplateTitle.fontSize = 24f;
            nameplateTitle.alignment = TextAlignmentOptions.Center;
            nameplateTitle.color = Color.white;

            var barsObject = new GameObject("Bars");
            barsObject.transform.SetParent(plateObject.transform, false);
            var barsRect = barsObject.AddComponent<RectTransform>();
            barsRect.anchorMin = new Vector2(0f, 0f);
            barsRect.anchorMax = new Vector2(1f, 1f);
            barsRect.pivot = new Vector2(0.5f, 0.5f);
            barsRect.offsetMin = new Vector2(NameplatePaddingX, NameplatePaddingBottom);
            barsRect.offsetMax = new Vector2(
                -NameplatePaddingX,
                -(NameplatePaddingTop + NameplateTitleHeight + NameplateTitleSpacing + NameplateContentOffsetY + NameplateBarsOffsetY));

            var barsLayout = barsObject.AddComponent<VerticalLayoutGroup>();
            barsLayout.spacing = StatusBarSpacing;
            barsLayout.childAlignment = TextAnchor.UpperCenter;
            barsLayout.childControlWidth = false;
            barsLayout.childControlHeight = false;
            barsLayout.childForceExpandWidth = false;
            barsLayout.childForceExpandHeight = false;

            CreateStatusBars(barsObject.transform, StatusBarWidth);
        }

        private void CreateStatusBars(Transform parent)
        {
            CreateStatusBars(parent, StatusBarWidth);
        }

        private void CreateStatusBars(Transform parent, float barWidth)
        {
            healthFill = CreateStatusBar(parent, "HealthBar", new Color(0.1f, 0.1f, 0.1f, 0.85f), new Color(0.2f, 0.85f, 0.2f, 1f), StatusBarHeight, barWidth, true, out healthLabel);
            resourceFill = CreateStatusBar(parent, "ResourceBar", new Color(0.25f, 0.25f, 0.25f, 0.85f), new Color(0.25f, 0.55f, 0.95f, 1f), StatusBarHeight, barWidth, true, out resourceLabel);
            resourceBarRoot = resourceFill != null ? resourceFill.transform.parent.gameObject : null;
            experienceFill = CreateStatusBar(parent, "ExperienceBar", new Color(1f, 1f, 1f, 0.2f), Color.white, ExperienceBarHeight, barWidth, false, out _);
        }

        private Image CreateStatusBar(Transform parent, string name, Color backgroundColor, Color fillColor, float height, float width, bool showText, out TextMeshProUGUI label)
        {
            var barObject = new GameObject(name);
            barObject.transform.SetParent(parent, false);
            var rect = barObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(width, height);

            var layout = barObject.AddComponent<LayoutElement>();
            layout.preferredWidth = width;
            layout.preferredHeight = height;

            var background = barObject.AddComponent<Image>();
            background.sprite = MenuStyling.GetRoundedButtonSprite();
            background.type = Image.Type.Sliced;
            background.color = backgroundColor;

            var fillObject = new GameObject("Fill");
            fillObject.transform.SetParent(barObject.transform, false);
            var fillRect = fillObject.AddComponent<RectTransform>();
            fillRect.anchorMin = Vector2.zero;
            fillRect.anchorMax = Vector2.one;
            var insetY = Mathf.Max(2f, height * 0.2f);
            fillRect.offsetMin = new Vector2(6f, insetY);
            fillRect.offsetMax = new Vector2(-6f, -insetY);

            var fillImage = fillObject.AddComponent<Image>();
            fillImage.sprite = GetSolidSprite();
            fillImage.type = Image.Type.Filled;
            fillImage.fillMethod = Image.FillMethod.Horizontal;
            fillImage.fillOrigin = 0;
            fillImage.fillAmount = 0f;
            fillImage.color = fillColor;

            label = null;
            if (showText)
            {
                var labelObject = new GameObject("Label");
                labelObject.transform.SetParent(barObject.transform, false);
                var labelRect = labelObject.AddComponent<RectTransform>();
                labelRect.anchorMin = Vector2.zero;
                labelRect.anchorMax = Vector2.one;
                labelRect.offsetMin = Vector2.zero;
                labelRect.offsetMax = Vector2.zero;

                label = labelObject.AddComponent<TextMeshProUGUI>();
                label.text = string.Empty;
                label.fontSize = 18f;
                label.alignment = TextAlignmentOptions.Center;
                label.color = Color.white;
            }

            return fillImage;
        }

        private Image CreateInlineBar(Transform parent, Vector2 size, Color fillColor, out TextMeshProUGUI label)
        {
            label = null;
            var barObject = new GameObject("InlineBar");
            barObject.transform.SetParent(parent, false);
            var rect = barObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.sizeDelta = size;

            var background = barObject.AddComponent<Image>();
            background.sprite = MenuStyling.GetRoundedButtonSprite();
            background.type = Image.Type.Sliced;
            background.color = new Color(0.1f, 0.1f, 0.12f, 0.85f);

            var fillObject = new GameObject("Fill");
            fillObject.transform.SetParent(barObject.transform, false);
            var fillRect = fillObject.AddComponent<RectTransform>();
            fillRect.anchorMin = Vector2.zero;
            fillRect.anchorMax = Vector2.one;
            fillRect.offsetMin = new Vector2(4f, 2f);
            fillRect.offsetMax = new Vector2(-4f, -2f);

            var fillImage = fillObject.AddComponent<Image>();
            fillImage.sprite = GetSolidSprite();
            fillImage.type = Image.Type.Filled;
            fillImage.fillMethod = Image.FillMethod.Horizontal;
            fillImage.color = fillColor;
            fillImage.fillAmount = 1f;
            return fillImage;
        }

        private void RefreshStatusBars()
        {
            var save = GameState.Instance != null ? GameState.Instance.CurrentSave : null;
            var player = save?.player;
            if (player == null)
            {
                SetFill(healthFill, 0f);
                SetFill(resourceFill, 0f);
                SetFill(experienceFill, 0f);
                if (resourceBarRoot != null)
                {
                    resourceBarRoot.SetActive(false);
                }
                if (nameplateTitle != null)
                {
                    nameplateTitle.text = FormatNameplateTitle(1);
                }
                if (healthLabel != null)
                {
                    healthLabel.text = "HP: 0/0";
                }
                if (resourceLabel != null)
                {
                    resourceLabel.text = "Resource: 0/0";
                }
                return;
            }

            if (nameplateTitle != null)
            {
                nameplateTitle.text = FormatNameplateTitle(player.level);
            }

            var resourceClass = save?.character?.characterClass ?? player.characterClass;
            var showResourceBar = resourceClass != CharacterClass.Unknown;
            if (resourceBarRoot != null)
            {
                resourceBarRoot.SetActive(showResourceBar);
            }

            var healthMax = Mathf.Max(1, player.maxHitPoints);
            SetFill(healthFill, (float)player.hitPoints / healthMax);
            if (healthLabel != null)
            {
                healthLabel.text = $"HP: {player.hitPoints}/{player.maxHitPoints}";
            }

            if (showResourceBar)
            {
                var resourceType = GetResourceTypeForPlayer(player);
                if (string.IsNullOrWhiteSpace(resourceType))
                {
                    resourceType = GetResourceTypeFromStats(player);
                }
                var (resourceCurrent, resourceMax) = GetPrimaryResource(player, resourceType);
                SetFill(resourceFill, resourceMax > 0 ? (float)resourceCurrent / resourceMax : 0f);
                if (resourceFill != null)
                {
                    resourceFill.color = GetResourceColor(resourceType);
                }
                if (resourceLabel != null)
                {
                    var label = GetResourceDisplayName(resourceType);
                    resourceLabel.text = $"{label}: {resourceCurrent}/{resourceMax}";
                }
            }

            var expProgress = GetExperienceProgress(player);
            SetFill(experienceFill, expProgress);
        }

        private void SetFill(Image fill, float value)
        {
            if (fill == null)
            {
                return;
            }

            fill.fillAmount = Mathf.Clamp01(value);
        }

        private (int current, int max) GetPrimaryResource(Player player, string resourceType)
        {
            if (string.Equals(resourceType, "mana", StringComparison.OrdinalIgnoreCase))
            {
                return (player.mana, player.maxMana);
            }

            if (string.Equals(resourceType, "rage", StringComparison.OrdinalIgnoreCase))
            {
                return (player.rage, player.maxRage);
            }

            if (string.Equals(resourceType, "energy", StringComparison.OrdinalIgnoreCase))
            {
                return (player.energy, player.maxEnergy);
            }

            if (player.maxMana > 0)
            {
                return (player.mana, player.maxMana);
            }

            if (player.maxRage > 0)
            {
                return (player.rage, player.maxRage);
            }

            if (player.maxEnergy > 0)
            {
                return (player.energy, player.maxEnergy);
            }

            return (0, 0);
        }

        private string GetResourceTypeForPlayer(Player player)
        {
            var save = GameState.Instance != null ? GameState.Instance.CurrentSave : null;
            var characterClass = save?.character?.characterClass ?? player.characterClass;
            if (characterClass == CharacterClass.Unknown)
            {
                return GetResourceTypeFromStats(player);
            }

            var classId = characterClass.ToString().ToLowerInvariant();
            var definition = characterCreationData != null ? characterCreationData.GetClassById(classId) : null;
            if (definition != null && !string.IsNullOrWhiteSpace(definition.resourceType))
            {
                return definition.resourceType;
            }

            return GetResourceTypeFromStats(player);
        }

        private static string GetResourceTypeFromStats(Player player)
        {
            if (player.maxMana > 0)
            {
                return "mana";
            }

            if (player.maxRage > 0)
            {
                return "rage";
            }

            if (player.maxEnergy > 0)
            {
                return "energy";
            }

            return null;
        }

        private static string GetResourceDisplayName(string resourceType)
        {
            if (string.IsNullOrWhiteSpace(resourceType))
            {
                return "Resource";
            }

            return char.ToUpperInvariant(resourceType[0]) + resourceType.Substring(1).ToLowerInvariant();
        }

        private static Color GetResourceColor(string resourceType)
        {
            if (string.Equals(resourceType, "rage", StringComparison.OrdinalIgnoreCase))
            {
                return new Color(0.85f, 0.2f, 0.2f, 1f);
            }

            if (string.Equals(resourceType, "energy", StringComparison.OrdinalIgnoreCase))
            {
                return new Color(0.2f, 0.9f, 0.4f, 1f);
            }

            return new Color(0.25f, 0.55f, 0.95f, 1f);
        }

        private static float GetExperienceProgress(Player player)
        {
            var max = Mathf.Max(1, player.level * 100);
            var current = player.experiencePoints;
            if (current < 0)
            {
                current = 0;
            }

            var progress = current % max;
            return Mathf.Clamp01((float)progress / max);
        }

        private string GetCurrentCharacterName()
        {
            var saveCharacter = GameState.Instance != null ? GameState.Instance.CurrentSave?.character : null;
            if (saveCharacter != null && !string.IsNullOrWhiteSpace(saveCharacter.name))
            {
                return saveCharacter.name;
            }

            var index = GetCurrentCharacterIndex();
            var storedName = PlayerPrefs.GetString($"{CharacterKeyPrefix}{index}_Name", "Adventurer");
            return string.IsNullOrWhiteSpace(storedName) ? "Adventurer" : storedName;
        }

        private string FormatNameplateTitle(int level)
        {
            var name = GetCurrentCharacterName();
            return $"<b><size=28>{name}</size></b>  Level {level}";
        }

        private void Awake()
        {
            if (GameObject.Find("GameUI") != null)
            {
                Destroy(gameObject);
            }
        }

        private void Start()
        {
            var existingUi = GameObject.Find("GameUI");
            if (existingUi != null)
            {
                Destroy(existingUi);
            }

            EnsureEventSystem();
            defaultFont = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            characterCreationData = CharacterCreationDataLoader.LoadFromResources();

            var canvas = CreateCanvas();
            rootCanvas = canvas;
            CreatePartyHud(canvas.transform);
            var settingsButton = CreateTopRightButton(canvas.transform, "Settings", () => TogglePanel(settingsPanel));
            CreateBottomRightButton(canvas.transform, "Menu", () => TogglePanel(combinedPanel));

            settingsPanel = CreateSettingsPanel(canvas.transform);
            combinedPanel = CreateCombinedPanel(canvas.transform);
            chestPanel = CreateChestPanel(canvas.transform);
            companionPanel = CreateCompanionPanel(canvas.transform);
            battlePanel = CreateBattlePanel(canvas.transform);
            itemActionPanel = CreateItemActionPanel(canvas.transform);
            actionBarPanel = CreateActionBar(canvas.transform);

            HideAllPanels();
        }

        private void Update()
        {
            if (Time.unscaledTime < nextStatusRefreshTime)
            {
                return;
            }

            nextStatusRefreshTime = Time.unscaledTime + 0.1f;
            RefreshStatusBars();
            RefreshPartyHud();

            if (Time.unscaledTime >= nextCombinedRefreshTime)
            {
                nextCombinedRefreshTime = Time.unscaledTime + 0.5f;
                RefreshSkillsTabVisibility();
                if (combinedPanel != null && combinedPanel.activeSelf && combinedTab == CombinedTab.Attributes)
                {
                    RefreshAttributesView();
                }
            }

            HandleItemActionDismiss();

            if (Time.unscaledTime >= nextActionBarRefreshTime)
            {
                nextActionBarRefreshTime = Time.unscaledTime + 0.5f;
                RefreshActionBarForCurrentActor();
            }
        }

        private void HandleItemActionDismiss()
        {
            if (itemActionPanel == null || !itemActionPanel.activeSelf)
            {
                return;
            }

            if (!Input.GetMouseButtonDown(0))
            {
                return;
            }

            var rect = itemActionPanel.GetComponent<RectTransform>();
            if (rect == null || rootCanvas == null)
            {
                CloseItemActionMenu();
                return;
            }

            var camera = rootCanvas.renderMode == RenderMode.ScreenSpaceCamera ? rootCanvas.worldCamera : null;
            if (!RectTransformUtility.RectangleContainsScreenPoint(rect, Input.mousePosition, camera))
            {
                CloseItemActionMenu();
            }
        }

        private void EnsureEventSystem()
        {
            if (FindFirstObjectByType<EventSystem>() != null)
            {
                return;
            }

            var eventSystemObject = new GameObject("EventSystem");
            eventSystemObject.AddComponent<EventSystem>();
            eventSystemObject.AddComponent<StandaloneInputModule>();
        }

        private Canvas CreateCanvas()
        {
            var canvasObject = new GameObject("GameUI");
            var canvas = canvasObject.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;

            var scaler = canvasObject.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920f, 1080f);
            scaler.matchWidthOrHeight = 0.5f;

            canvasObject.AddComponent<GraphicRaycaster>();
            return canvas;
        }

        private void CreateBottomRightButton(Transform parent, string label, UnityEngine.Events.UnityAction onClick)
        {
            var buttonObject = new GameObject($"{label}Button");
            buttonObject.transform.SetParent(parent, false);

            var rect = buttonObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(1f, 0f);
            rect.anchorMax = new Vector2(1f, 0f);
            rect.pivot = new Vector2(1f, 0f);
            rect.anchoredPosition = BottomRightMargin;
            rect.sizeDelta = new Vector2(ButtonWidth, ButtonHeight);

            var image = buttonObject.AddComponent<Image>();
            var iconSprite = GetButtonIconSprite(label);
            if (iconSprite != null)
            {
                image.sprite = iconSprite;
                image.type = Image.Type.Simple;
                image.color = Color.white;
                image.preserveAspect = true;
            }
            else
            {
                image.color = new Color(0.15f, 0.15f, 0.18f, 0.9f);
            }

            var button = buttonObject.AddComponent<Button>();
            button.onClick.AddListener(onClick);

            if (iconSprite == null)
            {
                var labelObject = new GameObject("Label");
                labelObject.transform.SetParent(buttonObject.transform, false);
                var labelRect = labelObject.AddComponent<RectTransform>();
                labelRect.anchorMin = Vector2.zero;
                labelRect.anchorMax = Vector2.one;
                labelRect.offsetMin = Vector2.zero;
                labelRect.offsetMax = Vector2.zero;

                var text = labelObject.AddComponent<Text>();
                text.text = label;
                text.font = defaultFont;
                text.fontSize = 14;
                text.alignment = TextAnchor.MiddleCenter;
                text.color = Color.white;
            }
        }

        private Button CreateTopRightButton(Transform parent, string label, UnityEngine.Events.UnityAction onClick)
        {
            var buttonObject = new GameObject($"{label}Button");
            buttonObject.transform.SetParent(parent, false);

            var rect = buttonObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(1f, 1f);
            rect.anchorMax = new Vector2(1f, 1f);
            rect.pivot = new Vector2(1f, 1f);
            rect.anchoredPosition = TopRightMargin;
            rect.sizeDelta = new Vector2(ButtonWidth, ButtonHeight);

            var image = buttonObject.AddComponent<Image>();
            var iconSprite = GetButtonIconSprite(label);
            if (iconSprite != null)
            {
                image.sprite = iconSprite;
                image.type = Image.Type.Simple;
                image.color = Color.white;
                image.preserveAspect = true;
            }
            else
            {
                image.color = new Color(0.15f, 0.15f, 0.18f, 0.9f);
            }

            var button = buttonObject.AddComponent<Button>();
            button.onClick.AddListener(onClick);

            if (iconSprite == null)
            {
                var labelObject = new GameObject("Label");
                labelObject.transform.SetParent(buttonObject.transform, false);
                var labelRect = labelObject.AddComponent<RectTransform>();
                labelRect.anchorMin = Vector2.zero;
                labelRect.anchorMax = Vector2.one;
                labelRect.offsetMin = Vector2.zero;
                labelRect.offsetMax = Vector2.zero;

                var text = labelObject.AddComponent<Text>();
                text.text = label;
                text.font = defaultFont;
                text.fontSize = 14;
                text.alignment = TextAnchor.MiddleCenter;
                text.color = Color.white;
            }

            return button;
        }

        private void CreateStackButton(Transform parent, string label, int index, UnityEngine.Events.UnityAction onClick)
        {
            var buttonObject = new GameObject($"{label}Button");
            buttonObject.transform.SetParent(parent, false);

            var rect = buttonObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(1f, 0f);
            rect.anchorMax = new Vector2(1f, 0f);
            rect.pivot = new Vector2(1f, 0f);
            rect.anchoredPosition = new Vector2(0f, index * (ButtonHeight + StackSpacing));
            rect.sizeDelta = new Vector2(ButtonWidth, ButtonHeight);

            var image = buttonObject.AddComponent<Image>();
            var iconSprite = GetButtonIconSprite(label);
            if (iconSprite != null)
            {
                image.sprite = iconSprite;
                image.type = Image.Type.Simple;
                image.color = Color.white;
                image.preserveAspect = true;
            }
            else
            {
                image.color = new Color(0.15f, 0.15f, 0.18f, 0.9f);
            }

            var button = buttonObject.AddComponent<Button>();
            button.onClick.AddListener(onClick);

            if (iconSprite == null)
            {
                var labelObject = new GameObject("Label");
                labelObject.transform.SetParent(buttonObject.transform, false);
                var labelRect = labelObject.AddComponent<RectTransform>();
                labelRect.anchorMin = Vector2.zero;
                labelRect.anchorMax = Vector2.one;
                labelRect.offsetMin = Vector2.zero;
                labelRect.offsetMax = Vector2.zero;

                var text = labelObject.AddComponent<Text>();
                text.text = label;
                text.font = defaultFont;
                text.fontSize = 14;
                text.alignment = TextAnchor.MiddleCenter;
                text.color = Color.white;
            }
        }

        private GameObject CreateSettingsPanel(Transform parent)
        {
            var panelObject = new GameObject("SettingsPanel");
            panelObject.transform.SetParent(parent, false);
            var rect = panelObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = SettingsPanelOffset;
            rect.sizeDelta = new Vector2(620f, 520f);

            MenuStyling.CreateBookPage(panelObject.transform, Vector2.zero, "SettingsPage");
            CreatePanelTitle(panelObject.transform, "Settings");
            CreateCloseButton(panelObject.transform, () => TogglePanel(panelObject));
            settingsContentRoot = CreateSettingsContentRoot(panelObject.transform);
            ShowSettingsView(SettingsView.Main);

            return panelObject;
        }

        private GameObject CreateCombinedPanel(Transform parent)
        {
            var panelObject = new GameObject("CombinedPanel");
            panelObject.transform.SetParent(parent, false);
            var rect = panelObject.AddComponent<RectTransform>();
            rect.anchorMin = Vector2.zero;
            rect.anchorMax = Vector2.one;
            rect.offsetMin = Vector2.zero;
            rect.offsetMax = Vector2.zero;

            MenuStyling.CreateBookPage(panelObject.transform, Vector2.zero, "CombinedPage");
            CreatePanelTitle(panelObject.transform, "Game Menu");
            CreateCloseButton(panelObject.transform, () => TogglePanel(panelObject));
            CreateCombinedTabRow(panelObject.transform);
            BuildCombinedTabContent(panelObject.transform);

            return panelObject;
        }

        private GameObject CreateChestPanel(Transform parent)
        {
            var panelObject = new GameObject("ChestPanel");
            panelObject.transform.SetParent(parent, false);
            var rect = panelObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = Vector2.zero;
            rect.sizeDelta = new Vector2(720f, 520f);

            MenuStyling.CreateBookPage(panelObject.transform, Vector2.zero, "ChestPage");
            chestTitle = CreateChestTitle(panelObject.transform);
            CreateCloseButton(panelObject.transform, CloseChest);

            var contentRoot = new GameObject("ChestContent");
            contentRoot.transform.SetParent(panelObject.transform, false);
            var contentRect = contentRoot.AddComponent<RectTransform>();
            contentRect.anchorMin = new Vector2(0.5f, 0.5f);
            contentRect.anchorMax = new Vector2(0.5f, 0.5f);
            contentRect.pivot = new Vector2(0.5f, 0.5f);
            contentRect.anchoredPosition = new Vector2(0f, -20f);
            contentRect.sizeDelta = new Vector2(620f, 320f);
            var contentImage = contentRoot.AddComponent<Image>();
            contentImage.color = new Color(0.18f, 0.16f, 0.12f, 0.6f);

            var itemsObject = new GameObject("Items");
            itemsObject.transform.SetParent(contentRoot.transform, false);
            chestItemsRoot = itemsObject.AddComponent<RectTransform>();
            chestItemsRoot.anchorMin = Vector2.zero;
            chestItemsRoot.anchorMax = Vector2.one;
            chestItemsRoot.pivot = new Vector2(0.5f, 0.5f);
            chestItemsRoot.offsetMin = new Vector2(16f, 16f);
            chestItemsRoot.offsetMax = new Vector2(-16f, -16f);

            var grid = itemsObject.AddComponent<GridLayoutGroup>();
            grid.cellSize = new Vector2(70f, 70f);
            grid.spacing = new Vector2(10f, 10f);
            grid.childAlignment = TextAnchor.UpperLeft;
            grid.constraint = GridLayoutGroup.Constraint.FixedColumnCount;
            grid.constraintCount = 7;

            chestTakeAllButton = MenuStyling.CreateBookButton(panelObject.transform, "Take All", new Vector2(200f, 48f), "ChestTakeAll");
            var takeAllRect = chestTakeAllButton.GetComponent<RectTransform>();
            takeAllRect.anchorMin = new Vector2(0.5f, 0f);
            takeAllRect.anchorMax = new Vector2(0.5f, 0f);
            takeAllRect.pivot = new Vector2(0.5f, 0f);
            takeAllRect.anchoredPosition = new Vector2(0f, 22f);
            chestTakeAllButton.onClick.RemoveAllListeners();
            chestTakeAllButton.onClick.AddListener(TakeAllFromChest);

            return panelObject;
        }

        private GameObject CreateCompanionPanel(Transform parent)
        {
            var panelObject = new GameObject("CompanionPanel");
            panelObject.transform.SetParent(parent, false);
            var rect = panelObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = Vector2.zero;
            rect.sizeDelta = new Vector2(720f, 420f);

            MenuStyling.CreateBookPage(panelObject.transform, Vector2.zero, "CompanionPage");
            companionTitle = CreatePanelTitleText(panelObject.transform, "Companion");
            companionCloseButton = CreateCloseButtonWithResult(panelObject.transform, CloseCompanionPanel);

            var bodyObject = new GameObject("CompanionBody");
            bodyObject.transform.SetParent(panelObject.transform, false);
            var bodyRect = bodyObject.AddComponent<RectTransform>();
            bodyRect.anchorMin = new Vector2(0.5f, 0.5f);
            bodyRect.anchorMax = new Vector2(0.5f, 0.5f);
            bodyRect.pivot = new Vector2(0.5f, 0.5f);
            bodyRect.anchoredPosition = new Vector2(0f, -20f);
            bodyRect.sizeDelta = new Vector2(600f, 200f);

            companionBody = bodyObject.AddComponent<TextMeshProUGUI>();
            companionBody.fontSize = 18f;
            companionBody.alignment = TextAlignmentOptions.TopLeft;
            companionBody.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : new Color(0.15f, 0.1f, 0.05f, 1f);
            companionBody.text = string.Empty;

            companionBefriendButton = MenuStyling.CreateBookButton(panelObject.transform, "Befriend", new Vector2(200f, 48f), "CompanionBefriend");
            var befriendRect = companionBefriendButton.GetComponent<RectTransform>();
            befriendRect.anchorMin = new Vector2(0.5f, 0f);
            befriendRect.anchorMax = new Vector2(0.5f, 0f);
            befriendRect.pivot = new Vector2(0.5f, 0f);
            befriendRect.anchoredPosition = new Vector2(0f, 26f);
            companionBefriendButton.onClick.RemoveAllListeners();
            companionBefriendButton.onClick.AddListener(TryBefriendActiveCompanion);

            return panelObject;
        }

        private GameObject CreateBattlePanel(Transform parent)
        {
            var panelObject = new GameObject("BattlePanel");
            panelObject.transform.SetParent(parent, false);
            var rect = panelObject.AddComponent<RectTransform>();
            rect.anchorMin = Vector2.zero;
            rect.anchorMax = Vector2.one;
            rect.offsetMin = Vector2.zero;
            rect.offsetMax = Vector2.zero;

            var background = panelObject.AddComponent<Image>();
            background.color = new Color(0f, 0f, 0f, 0.55f);

            var leftObject = new GameObject("BattleLeft");
            leftObject.transform.SetParent(panelObject.transform, false);
            var leftRect = leftObject.AddComponent<RectTransform>();
            leftRect.anchorMin = new Vector2(0f, 0.5f);
            leftRect.anchorMax = new Vector2(0f, 0.5f);
            leftRect.pivot = new Vector2(0f, 0.5f);
            leftRect.anchoredPosition = new Vector2(16f, 0f);
            leftRect.sizeDelta = new Vector2(320f, 200f);
            var leftLayout = leftObject.AddComponent<VerticalLayoutGroup>();
            leftLayout.spacing = 10f;
            leftLayout.childAlignment = TextAnchor.UpperLeft;
            leftLayout.childControlHeight = false;
            leftLayout.childControlWidth = false;
            leftLayout.childForceExpandHeight = false;
            leftLayout.childForceExpandWidth = false;
            battleLeftRoot = leftObject.transform;
            leftObject.SetActive(false);

            var rightObject = new GameObject("BattleRight");
            rightObject.transform.SetParent(panelObject.transform, false);
            var rightRect = rightObject.AddComponent<RectTransform>();
            rightRect.anchorMin = new Vector2(1f, 0.5f);
            rightRect.anchorMax = new Vector2(1f, 0.5f);
            rightRect.pivot = new Vector2(1f, 0.5f);
            rightRect.anchoredPosition = new Vector2(-16f, 0f);
            rightRect.sizeDelta = new Vector2(320f, 200f);
            var rightLayout = rightObject.AddComponent<VerticalLayoutGroup>();
            rightLayout.spacing = 10f;
            rightLayout.childAlignment = TextAnchor.UpperLeft;
            rightLayout.childControlHeight = false;
            rightLayout.childControlWidth = false;
            rightLayout.childForceExpandHeight = false;
            rightLayout.childForceExpandWidth = false;
            battleRightRoot = rightObject.transform;

            CreateCloseButton(panelObject.transform, CloseBattlePanel, new Vector2(-16f, -16f));

            return panelObject;
        }

        private void CreateCombinedTabRow(Transform parent)
        {
            var rowObject = new GameObject("CombinedTabRow");
            rowObject.transform.SetParent(parent, false);
            var rect = rowObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 1f);
            rect.anchorMax = new Vector2(0.5f, 1f);
            rect.pivot = new Vector2(0.5f, 1f);
            rect.anchoredPosition = new Vector2(0f, -80f);
            rect.sizeDelta = new Vector2(980f, 44f);

            var layout = rowObject.AddComponent<HorizontalLayoutGroup>();
            layout.spacing = 12f;
            layout.childControlWidth = false;
            layout.childControlHeight = true;
            layout.childForceExpandWidth = false;
            layout.childAlignment = TextAnchor.MiddleCenter;

            combinedInventoryTabButton = CreateCombinedTabButton(rowObject.transform, "Inventory", () => ShowCombinedTab(CombinedTab.Inventory));
            combinedSkillsTabButton = CreateCombinedTabButton(rowObject.transform, "Skills", () => ShowCombinedTab(CombinedTab.Skills));
            combinedAttributesTabButton = CreateCombinedTabButton(rowObject.transform, "Attributes", () => ShowCombinedTab(CombinedTab.Attributes));
            combinedBuildTabButton = CreateCombinedTabButton(rowObject.transform, "Build", () => ShowCombinedTab(CombinedTab.Build));
            combinedCompanionsTabButton = CreateCombinedTabButton(rowObject.transform, "Companions", () => ShowCombinedTab(CombinedTab.Companions));
        }

        private Button CreateCombinedTabButton(Transform parent, string label, UnityEngine.Events.UnityAction onClick)
        {
            var button = MenuStyling.CreateBookButton(parent, label, new Vector2(160f, 40f), $"{label}Button");
            button.onClick.RemoveAllListeners();
            button.onClick.AddListener(onClick);

            var text = button.GetComponentInChildren<TextMeshProUGUI>();
            if (text != null)
            {
                text.fontSize = 18f;
            }

            return button;
        }

        private void BuildCombinedTabContent(Transform parent)
        {
            combinedInventoryTab = CreateCombinedContentRoot(parent, "InventoryTab");
            combinedSkillsTab = CreateCombinedContentRoot(parent, "SkillsTab");
            combinedAttributesTab = CreateCombinedContentRoot(parent, "AttributesTab");
            combinedBuildTab = CreateCombinedContentRoot(parent, "BuildTab");
            combinedCompanionsTab = CreateCombinedContentRoot(parent, "CompanionsTab");

            BuildInventoryTab(combinedInventoryTab.transform);
            BuildSkillsTab(combinedSkillsTab.transform);
            BuildAttributesTab(combinedAttributesTab.transform);
            BuildBuildTab(combinedBuildTab.transform);
            BuildCompanionsTab(combinedCompanionsTab.transform);

            RefreshSkillsTabVisibility();
            ShowCombinedTab(CombinedTab.Inventory);
        }

        private GameObject CreateCombinedContentRoot(Transform parent, string name)
        {
            var contentObject = new GameObject(name);
            contentObject.transform.SetParent(parent, false);
            var rect = contentObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = new Vector2(0f, -20f);
            rect.sizeDelta = new Vector2(1100f, 620f);
            return contentObject;
        }

        private void ShowCombinedTab(CombinedTab tab)
        {
            combinedTab = tab;
            if (combinedInventoryTab != null) combinedInventoryTab.SetActive(tab == CombinedTab.Inventory);
            if (combinedSkillsTab != null) combinedSkillsTab.SetActive(tab == CombinedTab.Skills);
            if (combinedAttributesTab != null) combinedAttributesTab.SetActive(tab == CombinedTab.Attributes);
            if (combinedBuildTab != null) combinedBuildTab.SetActive(tab == CombinedTab.Build);
            if (combinedCompanionsTab != null) combinedCompanionsTab.SetActive(tab == CombinedTab.Companions);

            SetTabButtonState(combinedInventoryTabButton, tab == CombinedTab.Inventory);
            SetTabButtonState(combinedSkillsTabButton, tab == CombinedTab.Skills);
            SetTabButtonState(combinedAttributesTabButton, tab == CombinedTab.Attributes);
            SetTabButtonState(combinedBuildTabButton, tab == CombinedTab.Build);
            SetTabButtonState(combinedCompanionsTabButton, tab == CombinedTab.Companions);

            if (tab == CombinedTab.Attributes)
            {
                RefreshAttributesView();
            }

            if (tab == CombinedTab.Companions)
            {
                RefreshCompanionsTab();
            }
        }

        private void SetTabButtonState(Button button, bool isActive)
        {
            if (button == null)
            {
                return;
            }

            var image = button.GetComponent<Image>();
            if (image != null)
            {
                image.color = isActive ? Color.white : new Color(0.9f, 0.85f, 0.75f, 0.8f);
            }
        }

        private void BuildInventoryTab(Transform parent)
        {
            var layoutObject = new GameObject("InventoryLayout");
            layoutObject.transform.SetParent(parent, false);
            var rect = layoutObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = new Vector2(0f, 80f);
            rect.sizeDelta = new Vector2(1000f, 640f);

            var layout = layoutObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 10f;
            layout.childAlignment = TextAnchor.UpperCenter;
            layout.childControlWidth = false;
            layout.childControlHeight = false;
            layout.childForceExpandWidth = false;
            layout.childForceExpandHeight = false;

            CreateEquipmentSlots(layoutObject.transform);
            CreateVerticalSpacer(layoutObject.transform, 18f);
            CreateInventoryFilterRow(layoutObject.transform);
            CreateInventoryFilterContent(layoutObject.transform);

            ShowInventoryFilter(currentInventoryFilter);
        }

        private void CreateEquipmentSlots(Transform parent)
        {
            var slotsObject = new GameObject("EquipmentSlots");
            slotsObject.transform.SetParent(parent, false);
            var rect = slotsObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(460f, 360f);

            var layoutElement = slotsObject.AddComponent<LayoutElement>();
            layoutElement.preferredHeight = 320f;
            layoutElement.preferredWidth = 460f;

            CreateEquipmentSlot(slotsObject.transform, "Head", new Vector2(0f, 95f));
            CreateEquipmentSlot(slotsObject.transform, "Neck", new Vector2(90f, 65f));
            CreateEquipmentSlot(slotsObject.transform, "Chest", new Vector2(0f, 15f));
            CreateEquipmentSlot(slotsObject.transform, "Hands", new Vector2(-90f, -25f));
            CreateEquipmentSlot(slotsObject.transform, "Ring 1", new Vector2(90f, -25f));
            CreateEquipmentSlot(slotsObject.transform, "Ring 2", new Vector2(170f, -25f));
            CreateEquipmentSlot(slotsObject.transform, "Legs", new Vector2(0f, -65f));
            CreateEquipmentSlot(slotsObject.transform, "Feet", new Vector2(0f, -145f));
            CreateEquipmentSlot(slotsObject.transform, "Main Hand", new Vector2(-90f, -225f));
            CreateEquipmentSlot(slotsObject.transform, "Off-Hand", new Vector2(0f, -225f));
            CreateEquipmentSlot(slotsObject.transform, "Bow", new Vector2(90f, -225f));
        }

        private void CreateEquipmentSlot(Transform parent, string label, Vector2 position)
        {
            var slotObject = new GameObject($"{label}Slot");
            slotObject.transform.SetParent(parent, false);
            var rect = slotObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.sizeDelta = new Vector2(70f, 70f);
            rect.anchoredPosition = position;

            var image = slotObject.AddComponent<Image>();
            image.sprite = GetSolidSprite();
            image.type = Image.Type.Simple;
            image.color = new Color(0.2f, 0.2f, 0.22f, 0.9f);

            var labelObject = new GameObject("Label");
            labelObject.transform.SetParent(slotObject.transform, false);
            var labelRect = labelObject.AddComponent<RectTransform>();
            labelRect.anchorMin = Vector2.zero;
            labelRect.anchorMax = Vector2.one;
            labelRect.offsetMin = Vector2.zero;
            labelRect.offsetMax = Vector2.zero;

            var text = labelObject.AddComponent<TextMeshProUGUI>();
            text.text = label;
            text.fontSize = 10f;
            text.alignment = TextAlignmentOptions.Center;
            text.color = Color.white;

            var dropTarget = slotObject.AddComponent<EquipmentSlotDropTarget>();
            dropTarget.slotLabel = label;
            dropTarget.ui = this;

            var normalized = NormalizeSlotLabel(label);
            if (!string.IsNullOrWhiteSpace(normalized))
            {
                equipmentSlotRoots[normalized] = slotObject.transform;
            }
        }

        private void CreateInventoryFilterRow(Transform parent)
        {
            var rowObject = new GameObject("InventoryFilters");
            rowObject.transform.SetParent(parent, false);
            var rect = rowObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(980f, 44f);

            var layout = rowObject.AddComponent<HorizontalLayoutGroup>();
            layout.spacing = 10f;
            layout.childControlWidth = false;
            layout.childControlHeight = true;
            layout.childForceExpandWidth = false;
            layout.childAlignment = TextAnchor.MiddleCenter;

            var rowLayout = rowObject.AddComponent<LayoutElement>();
            rowLayout.preferredHeight = 44f;
            rowLayout.preferredWidth = 980f;

            inventoryFilterButtons.Clear();
            inventoryFilterPanels.Clear();

            CreateInventoryFilterButton(rowObject.transform, "All");
            CreateInventoryFilterButton(rowObject.transform, "Armor");
            CreateInventoryFilterButton(rowObject.transform, "Weapons");
            CreateInventoryFilterButton(rowObject.transform, "Consumables");
            CreateInventoryFilterButton(rowObject.transform, "Quest Items");
            CreateInventoryFilterButton(rowObject.transform, "Misc");
        }

        private void CreateInventoryFilterContent(Transform parent)
        {
            var contentObject = new GameObject("InventoryContent");
            contentObject.transform.SetParent(parent, false);
            var rect = contentObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(980f, 300f);

            var contentLayout = contentObject.AddComponent<LayoutElement>();
            contentLayout.preferredHeight = 300f;
            contentLayout.preferredWidth = 980f;

            CreateInventoryFilterPanel(contentObject.transform, "All", panel =>
            {
                CreateInventoryScrollGrid(panel.transform, 8, "All");
            });

            CreateInventoryFilterPanel(contentObject.transform, "Armor", panel =>
            {
                CreateInventoryScrollGrid(panel.transform, 8, "Armor");
            });

            CreateInventoryFilterPanel(contentObject.transform, "Weapons", panel =>
            {
                CreateInventoryScrollGrid(panel.transform, 8, "Weapons");
            });

            CreateInventoryFilterPanel(contentObject.transform, "Consumables", panel =>
            {
                CreateInventoryScrollGrid(panel.transform, 8, "Consumables");
            });

            CreateInventoryFilterPanel(contentObject.transform, "Quest Items", panel =>
            {
                CreateInventoryScrollGrid(panel.transform, 8, "Quest Items");
            });

            CreateInventoryFilterPanel(contentObject.transform, "Misc", panel =>
            {
                CreateInventoryScrollGrid(panel.transform, 8, "Misc");
            });
        }

        private void CreateInventoryFilterButton(Transform parent, string label)
        {
            var button = CreateCombinedTabButton(parent, label, () => ShowInventoryFilter(label));
            inventoryFilterButtons.Add(button);
        }

        private void CreateInventoryFilterPanel(Transform parent, string label, Action<GameObject> builder)
        {
            var panelObject = new GameObject($"{label}Panel");
            panelObject.transform.SetParent(parent, false);
            var rect = panelObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = Vector2.zero;
            rect.sizeDelta = new Vector2(980f, 300f);

            var layout = panelObject.AddComponent<LayoutElement>();
            layout.preferredWidth = 980f;
            layout.preferredHeight = 300f;

            builder?.Invoke(panelObject);
            inventoryFilterPanels.Add(panelObject);
        }

        private void CreateInventoryScrollGrid(Transform parent, int columns, string filterLabel)
        {
            var gridObject = new GameObject("InventoryGrid");
            gridObject.transform.SetParent(parent, false);
            var gridRect = gridObject.AddComponent<RectTransform>();
            gridRect.anchorMin = Vector2.zero;
            gridRect.anchorMax = Vector2.one;
            gridRect.pivot = new Vector2(0.5f, 0.5f);
            gridRect.offsetMin = Vector2.zero;
            gridRect.offsetMax = Vector2.zero;

            var gridLayout = gridObject.AddComponent<LayoutElement>();
            gridLayout.preferredWidth = 980f;
            gridLayout.preferredHeight = 300f;

            var gridBackground = gridObject.AddComponent<Image>();
            gridBackground.color = new Color(0.15f, 0.15f, 0.18f, 0.25f);

            var grid = gridObject.AddComponent<GridLayoutGroup>();
            var spacing = 8f;
            var columnsCount = Mathf.Max(1, columns);
            var cellSize = 70f;
            grid.cellSize = new Vector2(cellSize, cellSize);
            grid.spacing = new Vector2(spacing, spacing);
            grid.constraint = GridLayoutGroup.Constraint.FixedColumnCount;
            grid.constraintCount = columnsCount;
            grid.childAlignment = TextAnchor.UpperLeft;

            var items = BuildInventoryDisplayItems(filterLabel);
            for (var i = 0; i < items.Count; i++)
            {
                var displayItem = items[i];
                var slot = new GameObject($"Slot_{i + 1}");
                slot.transform.SetParent(gridObject.transform, false);
                var slotImage = slot.AddComponent<Image>();
                slotImage.color = new Color(0.25f, 0.25f, 0.28f, 1f);

                CreateInventoryItemIcon(slot.transform, displayItem.item, displayItem.definition, displayItem.count);

                var dropTarget = slot.AddComponent<InventorySlotDropTarget>();
                dropTarget.ui = this;
                dropTarget.targetItemId = displayItem.itemId;
                dropTarget.targetItem = displayItem.item;
            }

            var gridDropTarget = gridObject.AddComponent<InventorySlotDropTarget>();
            gridDropTarget.ui = this;
            gridDropTarget.targetItemId = null;
        }

        private int GetInventorySlotCount()
        {
            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player != null && player.inventory != null)
            {
                return Mathf.Max(24, player.inventory.Count);
            }

            return 48;
        }

        private List<Item> GetInventoryItems()
        {
            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player != null && player.inventory != null && player.inventory.Count > 0)
            {
                NormalizeInventoryStacks(player.inventory);
                Debug.Log($"[Inventory] Building UI from {player.inventory.Count} items.");
                return new List<Item>(player.inventory);
            }

            Debug.Log("[Inventory] No items found for UI.");
            return new List<Item>();
        }

        private void NormalizeInventoryStacks(List<Item> inventory)
        {
            if (inventory == null || inventory.Count == 0)
            {
                return;
            }

            var stackableById = new Dictionary<string, Item>(StringComparer.OrdinalIgnoreCase);
            for (var i = inventory.Count - 1; i >= 0; i--)
            {
                var item = inventory[i];
                if (item == null)
                {
                    inventory.RemoveAt(i);
                    continue;
                }

                var definition = GetItemDefinition(item);
                if (definition == null || !definition.stackable || string.IsNullOrWhiteSpace(item.id))
                {
                    if (item.quantity <= 0)
                    {
                        item.quantity = 1;
                    }
                    continue;
                }

                if (item.quantity <= 0)
                {
                    item.quantity = 1;
                }

                if (stackableById.TryGetValue(item.id, out var existing))
                {
                    existing.quantity += item.quantity;
                    inventory.RemoveAt(i);
                    continue;
                }

                stackableById[item.id] = item;
            }
        }

        private List<InventoryDisplayItem> BuildInventoryDisplayItems(string filterLabel)
        {
            var items = GetInventoryItems();
            var displayItems = new List<InventoryDisplayItem>();

            foreach (var item in items)
            {
                if (item == null)
                {
                    continue;
                }

                var definition = GetItemDefinition(item);
                if (!IsItemVisibleForFilter(definition, filterLabel))
                {
                    continue;
                }

                displayItems.Add(new InventoryDisplayItem
                {
                    item = item,
                    definition = definition,
                    count = definition != null && definition.stackable ? Mathf.Max(1, item.quantity) : 1,
                    itemId = item.id
                });
            }

            return displayItems;
        }

        private bool IsItemVisibleForFilter(ItemDefinition definition, string filterLabel)
        {
            if (definition == null || string.IsNullOrWhiteSpace(filterLabel) ||
                string.Equals(filterLabel, "All", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            var normalizedType = (definition.type ?? string.Empty).Replace(" ", string.Empty).Replace("-", string.Empty).ToLowerInvariant();
            var normalizedFilter = filterLabel.Replace(" ", string.Empty).Replace("-", string.Empty).ToLowerInvariant();

            switch (normalizedFilter)
            {
                case "armor":
                    return normalizedType == "armor";
                case "weapons":
                    return normalizedType == "weapon";
                case "consumables":
                    return normalizedType == "consumable";
                case "questitems":
                    return normalizedType == "quest" || normalizedType == "questitem" || normalizedType == "questitems";
                case "misc":
                    return normalizedType != "armor" &&
                           normalizedType != "weapon" &&
                           normalizedType != "consumable" &&
                           normalizedType != "quest" &&
                           normalizedType != "questitem" &&
                           normalizedType != "questitems";
                default:
                    return true;
            }
        }

        private void EnsureItemDefinitionsLoaded()
        {
            if (itemDefinitions.Count > 0)
            {
                return;
            }

            var asset = Resources.Load<TextAsset>("Prefabs/Objects/items");
            if (asset == null)
            {
                return;
            }

            var parsed = JsonUtility.FromJson<ItemList>(asset.text);
            if (parsed?.items == null)
            {
                return;
            }

            foreach (var item in parsed.items)
            {
                if (item != null && !string.IsNullOrWhiteSpace(item.id))
                {
                    itemDefinitions[item.id] = item;
                }
            }
        }

        private ItemDefinition GetItemDefinition(Item item)
        {
            if (item == null)
            {
                return null;
            }

            EnsureItemDefinitionsLoaded();
            if (!string.IsNullOrWhiteSpace(item.id) && itemDefinitions.TryGetValue(item.id, out var definition))
            {
                return definition;
            }

            return new ItemDefinition
            {
                id = item.id,
                name = item.name,
                description = item.description,
                type = "misc"
            };
        }

        private void CreateInventoryItemIcon(Transform parent, Item item, ItemDefinition definition, int quantity)
        {
            var iconObject = new GameObject("ItemIcon");
            iconObject.transform.SetParent(parent, false);
            var rect = iconObject.AddComponent<RectTransform>();
            rect.anchorMin = Vector2.zero;
            rect.anchorMax = Vector2.one;
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.offsetMin = new Vector2(4f, 4f);
            rect.offsetMax = new Vector2(-4f, -4f);

            var image = iconObject.AddComponent<Image>();
            image.sprite = GetSolidSprite();
            image.type = Image.Type.Simple;
            image.color = new Color(0.75f, 0.7f, 0.55f, 0.9f);
            image.raycastTarget = true;

            var labelObject = new GameObject("Label");
            labelObject.transform.SetParent(iconObject.transform, false);
            var labelRect = labelObject.AddComponent<RectTransform>();
            labelRect.anchorMin = Vector2.zero;
            labelRect.anchorMax = Vector2.one;
            labelRect.offsetMin = Vector2.zero;
            labelRect.offsetMax = Vector2.zero;

            var text = labelObject.AddComponent<TextMeshProUGUI>();
            text.text = !string.IsNullOrWhiteSpace(definition?.name) ? definition.name : (item?.name ?? "Item");
            text.fontSize = 10f;
            text.alignment = TextAlignmentOptions.Center;
            text.color = new Color(0.15f, 0.1f, 0.05f, 1f);

            var button = iconObject.AddComponent<Button>();
            button.onClick.RemoveAllListeners();
            button.onClick.AddListener(() => OpenItemActionMenu(item, definition));

            if (quantity > 1)
            {
                var quantityObject = new GameObject("Quantity");
                quantityObject.transform.SetParent(iconObject.transform, false);
                var quantityRect = quantityObject.AddComponent<RectTransform>();
                quantityRect.anchorMin = new Vector2(1f, 0f);
                quantityRect.anchorMax = new Vector2(1f, 0f);
                quantityRect.pivot = new Vector2(1f, 0f);
                quantityRect.anchoredPosition = new Vector2(-6f, 6f);
                quantityRect.sizeDelta = new Vector2(40f, 20f);

                var quantityText = quantityObject.AddComponent<TextMeshProUGUI>();
                quantityText.text = quantity.ToString();
                quantityText.fontSize = 16f;
                quantityText.alignment = TextAlignmentOptions.BottomRight;
                quantityText.color = new Color(0.1f, 0.08f, 0.05f, 1f);
            }

            var canvasGroup = iconObject.AddComponent<CanvasGroup>();
            var dragHandler = iconObject.AddComponent<InventoryItemDragHandler>();
            dragHandler.ui = this;
            dragHandler.definition = definition;
            dragHandler.item = item;
            dragHandler.canvasGroup = canvasGroup;
            dragHandler.rectTransform = rect;
            dragHandler.IsEquipped = false;
        }

        private void ShowInventoryFilter(string label)
        {
            currentInventoryFilter = label;
            for (var i = 0; i < inventoryFilterPanels.Count; i++)
            {
                var panel = inventoryFilterPanels[i];
                panel.SetActive(string.Equals(panel.name, $"{label}Panel", StringComparison.OrdinalIgnoreCase));
            }

            for (var i = 0; i < inventoryFilterButtons.Count; i++)
            {
                var button = inventoryFilterButtons[i];
                var buttonLabel = button != null ? button.name.Replace("Button", string.Empty) : string.Empty;
                SetSubTabButtonState(button, string.Equals(buttonLabel, label, StringComparison.OrdinalIgnoreCase));
            }
        }

        private void CreateVerticalSpacer(Transform parent, float height)
        {
            var spacer = new GameObject("VerticalSpacer");
            spacer.transform.SetParent(parent, false);
            var layout = spacer.AddComponent<LayoutElement>();
            layout.preferredHeight = height;
        }

        private bool TryEquipItemToSlot(InventoryItemDragHandler dragHandler, string slotLabel)
        {
            if (dragHandler == null)
            {
                return false;
            }

            var definition = dragHandler.definition;
            if (!IsItemCompatibleWithSlot(definition, slotLabel))
            {
                return false;
            }

            var slotTransform = dragHandler.CurrentDropTarget != null ? dragHandler.CurrentDropTarget.transform : null;
            if (slotTransform == null)
            {
                return false;
            }

            if (slotTransform.GetComponentInChildren<InventoryItemDragHandler>() != null)
            {
                return false;
            }

            RemoveItemFromInventory(dragHandler.item);
            dragHandler.transform.SetParent(slotTransform, false);
            dragHandler.rectTransform.anchorMin = Vector2.zero;
            dragHandler.rectTransform.anchorMax = Vector2.one;
            dragHandler.rectTransform.pivot = new Vector2(0.5f, 0.5f);
            dragHandler.rectTransform.offsetMin = new Vector2(6f, 6f);
            dragHandler.rectTransform.offsetMax = new Vector2(-6f, -6f);
            dragHandler.rectTransform.anchoredPosition = Vector2.zero;
            dragHandler.rectTransform.sizeDelta = Vector2.zero;
            dragHandler.rectTransform.localScale = Vector3.one;
            dragHandler.IsEquipped = true;
            dragHandler.EquippedSlotLabel = slotLabel;

            ApplyEquipmentToCharacter(slotLabel, definition);
            RefreshInventoryUI();
            return true;
        }

        private bool RemoveItemFromInventory(Item item)
        {
            if (item == null)
            {
                return false;
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || player.inventory == null)
            {
                return false;
            }

            var definition = GetItemDefinition(item);
            if (definition != null && definition.stackable)
            {
                for (var i = 0; i < player.inventory.Count; i++)
                {
                    var entry = player.inventory[i];
                    if (entry == null || !string.Equals(entry.id, item.id, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    var currentCount = Mathf.Max(1, entry.quantity);
                    if (currentCount > 1)
                    {
                        entry.quantity = currentCount - 1;
                    }
                    else
                    {
                        player.inventory.RemoveAt(i);
                    }

                    return true;
                }

                return false;
            }

            for (var i = 0; i < player.inventory.Count; i++)
            {
                if (ReferenceEquals(player.inventory[i], item))
                {
                    player.inventory.RemoveAt(i);
                    return true;
                }
            }

            for (var i = 0; i < player.inventory.Count; i++)
            {
                if (player.inventory[i] != null && string.Equals(player.inventory[i].id, item.id, StringComparison.OrdinalIgnoreCase))
                {
                    player.inventory.RemoveAt(i);
                    return true;
                }
            }

            return false;
        }

        private void AddItemToInventory(Item item)
        {
            if (item == null)
            {
                return;
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || player.inventory == null)
            {
                return;
            }

            var definition = GetItemDefinition(item);
            if (definition != null && definition.stackable)
            {
                NormalizeInventoryStacks(player.inventory);
                var quantityToAdd = Mathf.Max(1, item.quantity);
                for (var i = 0; i < player.inventory.Count; i++)
                {
                    var entry = player.inventory[i];
                    if (entry == null || !string.Equals(entry.id, item.id, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    entry.quantity = Mathf.Max(1, entry.quantity) + quantityToAdd;
                    return;
                }

                item.quantity = quantityToAdd;
                player.inventory.Add(item);
                return;
            }

            player.inventory.Add(item);
        }

        private bool HasInventoryItem(string itemId)
        {
            if (string.IsNullOrWhiteSpace(itemId))
            {
                return false;
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || player.inventory == null)
            {
                return false;
            }

            NormalizeInventoryStacks(player.inventory);
            for (var i = 0; i < player.inventory.Count; i++)
            {
                var entry = player.inventory[i];
                if (entry == null || !string.Equals(entry.id, itemId, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                return Mathf.Max(1, entry.quantity) > 0;
            }

            return false;
        }

        private bool RemoveItemById(string itemId)
        {
            if (string.IsNullOrWhiteSpace(itemId))
            {
                return false;
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || player.inventory == null)
            {
                return false;
            }

            NormalizeInventoryStacks(player.inventory);
            for (var i = 0; i < player.inventory.Count; i++)
            {
                var entry = player.inventory[i];
                if (entry == null || !string.Equals(entry.id, itemId, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var definition = GetItemDefinition(entry);
                if (definition != null && definition.stackable)
                {
                    var quantity = Mathf.Max(1, entry.quantity);
                    if (quantity > 1)
                    {
                        entry.quantity = quantity - 1;
                    }
                    else
                    {
                        player.inventory.RemoveAt(i);
                    }

                    return true;
                }

                player.inventory.RemoveAt(i);
                return true;
            }

            return false;
        }

        private void HandleInventoryDrop(InventoryItemDragHandler dragHandler, string targetItemId, Item targetItem)
        {
            if (dragHandler == null || dragHandler.item == null)
            {
                return;
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || player.inventory == null)
            {
                return;
            }

            if (dragHandler.IsEquipped)
            {
                AddItemToInventory(dragHandler.item);
                dragHandler.IsEquipped = false;
                dragHandler.EquippedSlotLabel = null;
                Destroy(dragHandler.gameObject);
                RefreshInventoryUI();
                return;
            }

            if (dragHandler.definition != null && dragHandler.definition.stackable)
            {
                var sourceId = dragHandler.item.id;
                if (string.IsNullOrWhiteSpace(sourceId))
                {
                    return;
                }

                if (!string.IsNullOrWhiteSpace(targetItemId) &&
                    string.Equals(sourceId, targetItemId, StringComparison.OrdinalIgnoreCase))
                {
                    return;
                }

                MoveInventoryGroup(sourceId, targetItemId);
                Destroy(dragHandler.gameObject);
                RefreshInventoryUI();
                return;
            }

            MoveInventoryItem(dragHandler.item, targetItem);
            Destroy(dragHandler.gameObject);
            RefreshInventoryUI();
        }

        private void MoveInventoryGroup(string sourceItemId, string targetItemId)
        {
            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || player.inventory == null)
            {
                return;
            }

            NormalizeInventoryStacks(player.inventory);
            var inventory = player.inventory;
            var movedItems = new List<Item>();
            for (var i = inventory.Count - 1; i >= 0; i--)
            {
                if (inventory[i] != null &&
                    string.Equals(inventory[i].id, sourceItemId, StringComparison.OrdinalIgnoreCase))
                {
                    movedItems.Insert(0, inventory[i]);
                    inventory.RemoveAt(i);
                }
            }

            if (movedItems.Count == 0)
            {
                return;
            }

            if (string.IsNullOrWhiteSpace(targetItemId))
            {
                inventory.AddRange(movedItems);
                return;
            }

            var insertIndex = inventory.FindIndex(item =>
                item != null && string.Equals(item.id, targetItemId, StringComparison.OrdinalIgnoreCase));
            if (insertIndex < 0)
            {
                inventory.AddRange(movedItems);
                return;
            }

            inventory.InsertRange(insertIndex, movedItems);
        }

        private void MoveInventoryItem(Item sourceItem, Item targetItem)
        {
            if (sourceItem == null)
            {
                return;
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || player.inventory == null)
            {
                return;
            }

            var inventory = player.inventory;
            var sourceIndex = inventory.FindIndex(item => ReferenceEquals(item, sourceItem));
            if (sourceIndex < 0)
            {
                return;
            }

            inventory.RemoveAt(sourceIndex);

            if (targetItem == null)
            {
                inventory.Add(sourceItem);
                return;
            }

            var targetIndex = inventory.FindIndex(item => ReferenceEquals(item, targetItem));
            if (targetIndex < 0)
            {
                inventory.Add(sourceItem);
                return;
            }

            inventory.Insert(targetIndex, sourceItem);
        }

        private bool IsItemCompatibleWithSlot(ItemDefinition definition, string slotLabel)
        {
            if (definition == null || string.IsNullOrWhiteSpace(slotLabel))
            {
                return false;
            }

            var normalizedSlot = NormalizeSlotLabel(slotLabel);
            var normalizedType = NormalizeSlotLabel(definition.type);
            if (definition.armorData != null && !string.IsNullOrWhiteSpace(definition.armorData.slot))
            {
                if (!string.Equals(normalizedType, "armor", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }

                var armorSlot = NormalizeSlotLabel(definition.armorData.slot);
                return string.Equals(armorSlot, normalizedSlot, StringComparison.OrdinalIgnoreCase);
            }

            if (definition.weaponData != null)
            {
                if (!string.Equals(normalizedType, "weapon", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }

                if (string.Equals(definition.weaponData.weaponType, "bow", StringComparison.OrdinalIgnoreCase))
                {
                    return string.Equals(normalizedSlot, "bow", StringComparison.OrdinalIgnoreCase);
                }

                if (string.Equals(definition.weaponData.weaponType, "shield", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(definition.weaponData.weaponType, "offhand", StringComparison.OrdinalIgnoreCase))
                {
                    return string.Equals(normalizedSlot, "offhand", StringComparison.OrdinalIgnoreCase);
                }

                return string.Equals(normalizedSlot, "mainhand", StringComparison.OrdinalIgnoreCase);
            }

            return false;
        }

        private string NormalizeSlotLabel(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return string.Empty;
            }

            return value.Replace(" ", string.Empty).Replace("-", string.Empty).ToLowerInvariant();
        }

        private void ApplyEquipmentToCharacter(string slotLabel, ItemDefinition definition)
        {
            var playerObject = GameObject.Find("PlayerCharacter");
            if (playerObject == null || definition == null)
            {
                return;
            }

            var targetCategory = GetSpriteCategoryForSlot(slotLabel, definition);
            if (string.IsNullOrWhiteSpace(targetCategory))
            {
                return;
            }

            var resolvers = playerObject.GetComponentsInChildren<SpriteResolver>(true);
            foreach (var resolver in resolvers)
            {
                if (resolver == null)
                {
                    continue;
                }

                var category = resolver.GetCategory();
                if (string.Equals(category, targetCategory, StringComparison.OrdinalIgnoreCase))
                {
                    resolver.SetCategoryAndLabel(category, definition.id);
                    break;
                }
            }
        }

        private string GetSpriteCategoryForSlot(string slotLabel, ItemDefinition definition)
        {
            var normalizedSlot = NormalizeSlotLabel(slotLabel);
            switch (normalizedSlot)
            {
                case "head":
                    return "Head";
                case "chest":
                    return "Chest";
                case "legs":
                    return "Legs";
                case "hands":
                    return "Hands";
                case "mainhand":
                    return "WeaponMainHand";
                case "offhand":
                    return "WeaponOffHand";
                case "bow":
                    return "WeaponMainHand";
                case "neck":
                case "ring1":
                case "ring2":
                    return "Accessory";
                default:
                    return null;
            }
        }

        private void BuildSkillsTab(Transform parent)
        {
            CreatePlaceholderText(parent, "Skills will unlock once a class is chosen.");
        }

        private void BuildAttributesTab(Transform parent)
        {
            var layoutObject = new GameObject("AttributesLayout");
            layoutObject.transform.SetParent(parent, false);
            var rect = layoutObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = new Vector2(0f, 30f);
            rect.sizeDelta = new Vector2(900f, 520f);

            var layout = layoutObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 12f;
            layout.childAlignment = TextAnchor.UpperCenter;
            layout.childControlWidth = false;
            layout.childControlHeight = false;
            layout.childForceExpandWidth = false;
            layout.childForceExpandHeight = false;

            var pointsObject = new GameObject("AttributePoints");
            pointsObject.transform.SetParent(layoutObject.transform, false);
            var pointsRect = pointsObject.AddComponent<RectTransform>();
            pointsRect.sizeDelta = new Vector2(320f, 40f);

            attributePointsLabel = pointsObject.AddComponent<TextMeshProUGUI>();
            attributePointsLabel.text = "Attribute Points: 0";
            attributePointsLabel.fontSize = 22f;
            attributePointsLabel.alignment = TextAlignmentOptions.Center;
            attributePointsLabel.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : new Color(0.15f, 0.1f, 0.05f, 1f);

            var rowsObject = new GameObject("AttributeRows");
            rowsObject.transform.SetParent(layoutObject.transform, false);
            var rowsRect = rowsObject.AddComponent<RectTransform>();
            rowsRect.sizeDelta = new Vector2(760f, 420f);

            var rowsLayout = rowsObject.AddComponent<VerticalLayoutGroup>();
            rowsLayout.spacing = 12f;
            rowsLayout.childAlignment = TextAnchor.UpperCenter;
            rowsLayout.childControlWidth = false;
            rowsLayout.childControlHeight = false;
            rowsLayout.childForceExpandWidth = false;
            rowsLayout.childForceExpandHeight = false;

            attributeValueLabels.Clear();
            attributeMinusButtons.Clear();
            attributePlusButtons.Clear();
            BuildAttributeRow(rowsObject.transform, Ability.Strength, "Strength");
            BuildAttributeRow(rowsObject.transform, Ability.Dexterity, "Dexterity");
            BuildAttributeRow(rowsObject.transform, Ability.Constitution, "Constitution");
            BuildAttributeRow(rowsObject.transform, Ability.Intelligence, "Intelligence");
            BuildAttributeRow(rowsObject.transform, Ability.Wisdom, "Wisdom");
            BuildAttributeRow(rowsObject.transform, Ability.Charisma, "Charisma");

            var actionRow = new GameObject("AttributeActions");
            actionRow.transform.SetParent(layoutObject.transform, false);
            var actionRect = actionRow.AddComponent<RectTransform>();
            actionRect.sizeDelta = new Vector2(320f, 44f);

            var actionLayout = actionRow.AddComponent<HorizontalLayoutGroup>();
            actionLayout.spacing = 12f;
            actionLayout.childAlignment = TextAnchor.MiddleCenter;
            actionLayout.childControlWidth = false;
            actionLayout.childControlHeight = false;
            actionLayout.childForceExpandWidth = false;
            actionLayout.childForceExpandHeight = false;

            attributeResetButton = CreateCombinedTabButton(actionRow.transform, "Reset", ResetPendingAttributes);
            attributeSaveButton = CreateCombinedTabButton(actionRow.transform, "Save", CommitPendingAttributes);

            RefreshAttributesView();
        }

        private void BuildAttributeRow(Transform parent, Ability ability, string label)
        {
            var rowObject = new GameObject($"{label}Row");
            rowObject.transform.SetParent(parent, false);
            var rect = rowObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(760f, 56f);

            var layout = rowObject.AddComponent<HorizontalLayoutGroup>();
            layout.spacing = 12f;
            layout.childAlignment = TextAnchor.MiddleCenter;
            layout.childControlWidth = false;
            layout.childControlHeight = false;
            layout.childForceExpandWidth = false;
            layout.childForceExpandHeight = false;

            var nameObject = new GameObject("Name");
            nameObject.transform.SetParent(rowObject.transform, false);
            var nameRect = nameObject.AddComponent<RectTransform>();
            nameRect.sizeDelta = new Vector2(240f, 40f);

            var nameText = nameObject.AddComponent<TextMeshProUGUI>();
            nameText.text = label;
            nameText.fontSize = 20f;
            nameText.alignment = TextAlignmentOptions.Left;
            nameText.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : new Color(0.15f, 0.1f, 0.05f, 1f);

            var minusButton = CreateCombinedTabButton(rowObject.transform, "-", () => AdjustAttribute(ability, -1));
            var minusRect = minusButton.GetComponent<RectTransform>();
            if (minusRect != null)
            {
                minusRect.sizeDelta = new Vector2(50f, 36f);
            }
            attributeMinusButtons[ability] = minusButton;

            var valueObject = new GameObject("Value");
            valueObject.transform.SetParent(rowObject.transform, false);
            var valueRect = valueObject.AddComponent<RectTransform>();
            valueRect.sizeDelta = new Vector2(80f, 40f);

            var valueText = valueObject.AddComponent<TextMeshProUGUI>();
            valueText.text = "0";
            valueText.fontSize = 20f;
            valueText.alignment = TextAlignmentOptions.Center;
            valueText.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : new Color(0.15f, 0.1f, 0.05f, 1f);
            attributeValueLabels[ability] = valueText;

            var plusButton = CreateCombinedTabButton(rowObject.transform, "+", () => AdjustAttribute(ability, 1));
            var plusRect = plusButton.GetComponent<RectTransform>();
            if (plusRect != null)
            {
                plusRect.sizeDelta = new Vector2(50f, 36f);
            }
            attributePlusButtons[ability] = plusButton;
        }

        private void RefreshAttributesView()
        {
            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            var available = player != null ? Mathf.Max(0, player.attributePoints - pendingAttributePoints) : 0;
            if (attributePointsLabel != null)
            {
                attributePointsLabel.text = $"Attribute Points: {available}";
            }

            foreach (var entry in attributeValueLabels)
            {
                if (entry.Value == null)
                {
                    continue;
                }

                var baseScore = player != null ? player.abilityScores.ScoreFor(entry.Key) : 0;
                entry.Value.text = (baseScore + GetPendingAllocation(entry.Key)).ToString();
            }

            foreach (var entry in attributeMinusButtons)
            {
                if (entry.Value != null)
                {
                    entry.Value.interactable = GetPendingAllocation(entry.Key) > 0;
                }
            }

            foreach (var entry in attributePlusButtons)
            {
                if (entry.Value != null)
                {
                    entry.Value.interactable = available > 0;
                }
            }

            if (attributeSaveButton != null)
            {
                attributeSaveButton.interactable = pendingAttributePoints > 0;
            }

            if (attributeResetButton != null)
            {
                attributeResetButton.interactable = pendingAttributePoints > 0;
            }
        }

        private void AdjustAttribute(Ability ability, int delta)
        {
            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || delta == 0)
            {
                return;
            }

            var available = Mathf.Max(0, player.attributePoints - pendingAttributePoints);
            if (delta > 0)
            {
                if (available <= 0)
                {
                    return;
                }
                pendingAttributeAllocations[ability] = GetPendingAllocation(ability) + 1;
                pendingAttributePoints += 1;
            }
            else
            {
                if (GetPendingAllocation(ability) <= 0)
                {
                    return;
                }
                pendingAttributeAllocations[ability] = GetPendingAllocation(ability) - 1;
                pendingAttributePoints = Mathf.Max(0, pendingAttributePoints - 1);
            }

            RefreshAttributesView();
        }

        private int GetPendingAllocation(Ability ability)
        {
            return pendingAttributeAllocations.TryGetValue(ability, out var value) ? value : 0;
        }

        private void ResetPendingAttributes()
        {
            pendingAttributeAllocations.Clear();
            pendingAttributePoints = 0;
            RefreshAttributesView();
        }

        private void CommitPendingAttributes()
        {
            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || pendingAttributePoints <= 0)
            {
                return;
            }

            var scores = player.abilityScores;
            foreach (var entry in pendingAttributeAllocations)
            {
                var amount = entry.Value;
                if (amount <= 0)
                {
                    continue;
                }

                switch (entry.Key)
                {
                    case Ability.Strength:
                        scores.strength += amount;
                        break;
                    case Ability.Dexterity:
                        scores.dexterity += amount;
                        break;
                    case Ability.Constitution:
                        scores.constitution += amount;
                        break;
                    case Ability.Intelligence:
                        scores.intelligence += amount;
                        break;
                    case Ability.Wisdom:
                        scores.wisdom += amount;
                        break;
                    case Ability.Charisma:
                        scores.charisma += amount;
                        break;
                }
            }

            player.abilityScores = scores;
            player.attributePoints = Mathf.Max(0, player.attributePoints - pendingAttributePoints);
            pendingAttributeAllocations.Clear();
            pendingAttributePoints = 0;
            RefreshAttributesView();
        }

        private void BuildBuildTab(Transform parent)
        {
            var layoutObject = new GameObject("BuildLayout");
            layoutObject.transform.SetParent(parent, false);
            var rect = layoutObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = Vector2.zero;
            rect.sizeDelta = new Vector2(1000f, 560f);

            var layout = layoutObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 18f;
            layout.childAlignment = TextAnchor.UpperCenter;
            layout.childControlWidth = false;
            layout.childControlHeight = false;
            layout.childForceExpandWidth = false;
            layout.childForceExpandHeight = false;

            var structures = LoadBuildableStructures();
            var uniqueStructures = new List<BuildableStructureDefinition>();
            var structureIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var structure in structures)
            {
                if (structure == null || string.IsNullOrWhiteSpace(structure.id))
                {
                    continue;
                }

                if (structureIds.Add(structure.id))
                {
                    uniqueStructures.Add(structure);
                }
            }

            var structureTypes = new List<string>();
            var seenTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var structure in uniqueStructures)
            {
                if (string.IsNullOrWhiteSpace(structure.structureType))
                {
                    continue;
                }

                if (seenTypes.Add(structure.structureType))
                {
                    structureTypes.Add(structure.structureType);
                }
            }

            var tabRow = CreateBuildTypeRow(layoutObject.transform, structureTypes);
            var contentRoot = CreateBuildTypeContent(layoutObject.transform, uniqueStructures, structureTypes);

            currentBuildType = structureTypes.Count > 0 ? structureTypes[0] : null;
            ShowBuildType(currentBuildType);

            if (uniqueStructures.Count == 0)
            {
                CreatePlaceholderText(layoutObject.transform, "No buildable structures found.");
            }
        }

        private void BuildCompanionsTab(Transform parent)
        {
            var layoutObject = new GameObject("CompanionsLayout");
            layoutObject.transform.SetParent(parent, false);
            var rect = layoutObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = Vector2.zero;
            rect.sizeDelta = new Vector2(1000f, 560f);

            var layout = layoutObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 16f;
            layout.childAlignment = TextAnchor.UpperCenter;
            layout.childControlWidth = false;
            layout.childControlHeight = false;
            layout.childForceExpandWidth = false;
            layout.childForceExpandHeight = false;

            var titleObject = new GameObject("CompanionsTitle");
            titleObject.transform.SetParent(layoutObject.transform, false);
            var titleRect = titleObject.AddComponent<RectTransform>();
            titleRect.sizeDelta = new Vector2(820f, 40f);
            var titleText = titleObject.AddComponent<TextMeshProUGUI>();
            titleText.text = "Your Companions";
            titleText.fontSize = 24f;
            titleText.alignment = TextAlignmentOptions.Center;
            titleText.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : new Color(0.15f, 0.1f, 0.05f, 1f);

            var listObject = new GameObject("CompanionsList");
            listObject.transform.SetParent(layoutObject.transform, false);
            var listRect = listObject.AddComponent<RectTransform>();
            listRect.sizeDelta = new Vector2(820f, 420f);
            var listLayout = listObject.AddComponent<VerticalLayoutGroup>();
            listLayout.spacing = 8f;
            listLayout.childAlignment = TextAnchor.UpperLeft;
            listLayout.childControlWidth = false;
            listLayout.childControlHeight = false;
            listLayout.childForceExpandWidth = false;
            listLayout.childForceExpandHeight = false;
            companionsListRoot = listObject.transform;

            RefreshCompanionsTab();
        }

        private Transform CreateBuildTypeRow(Transform parent, List<string> types)
        {
            var containerObject = new GameObject("BuildTypeRow");
            containerObject.transform.SetParent(parent, false);
            var rect = containerObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(980f, 44f);

            var containerLayout = containerObject.AddComponent<HorizontalLayoutGroup>();
            containerLayout.childAlignment = TextAnchor.MiddleCenter;
            containerLayout.childControlWidth = false;
            containerLayout.childControlHeight = true;
            containerLayout.childForceExpandWidth = false;
            containerLayout.spacing = 0f;

            var rowLayout = containerObject.AddComponent<LayoutElement>();
            rowLayout.preferredWidth = 980f;
            rowLayout.preferredHeight = 44f;

            var rowObject = new GameObject("RowContent");
            rowObject.transform.SetParent(containerObject.transform, false);
            var rowRect = rowObject.AddComponent<RectTransform>();
            rowRect.sizeDelta = new Vector2(0f, 44f);

            var layout = rowObject.AddComponent<HorizontalLayoutGroup>();
            layout.spacing = 10f;
            layout.childControlWidth = false;
            layout.childControlHeight = true;
            layout.childForceExpandWidth = false;
            layout.childAlignment = TextAnchor.MiddleCenter;

            var fitter = rowObject.AddComponent<ContentSizeFitter>();
            fitter.horizontalFit = ContentSizeFitter.FitMode.PreferredSize;
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;

            buildTypeButtons.Clear();
            buildTypePanels.Clear();

            foreach (var type in types)
            {
                var button = CreateCombinedTabButton(rowObject.transform, type, () => ShowBuildType(type));
                buildTypeButtons.Add(button);
            }

            return containerObject.transform;
        }

        private Transform CreateBuildTypeContent(Transform parent, List<BuildableStructureDefinition> structures, List<string> types)
        {
            var contentObject = new GameObject("BuildTypeContent");
            contentObject.transform.SetParent(parent, false);
            var rect = contentObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(980f, 420f);

            var contentLayout = contentObject.AddComponent<LayoutElement>();
            contentLayout.preferredWidth = 980f;
            contentLayout.preferredHeight = 420f;

            foreach (var type in types)
            {
                var panelObject = new GameObject($"{type}Panel");
                panelObject.transform.SetParent(contentObject.transform, false);
                var panelRect = panelObject.AddComponent<RectTransform>();
                panelRect.anchorMin = new Vector2(0.5f, 0.5f);
                panelRect.anchorMax = new Vector2(0.5f, 0.5f);
                panelRect.pivot = new Vector2(0.5f, 0.5f);
                panelRect.anchoredPosition = Vector2.zero;
                panelRect.sizeDelta = new Vector2(980f, 420f);

                var layout = panelObject.AddComponent<VerticalLayoutGroup>();
                layout.spacing = 12f;
                layout.childAlignment = TextAnchor.UpperCenter;
                layout.childControlWidth = false;
                layout.childControlHeight = false;
                layout.childForceExpandWidth = false;
                layout.childForceExpandHeight = false;

                foreach (var structure in structures)
                {
                    if (!string.Equals(structure.structureType, type, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    CreateBuildStructureCard(panelObject.transform, structure);
                }

                buildTypePanels.Add(panelObject);
            }

            return contentObject.transform;
        }

        private void CreateBuildStructureCard(Transform parent, BuildableStructureDefinition structure)
        {
            var cardObject = new GameObject($"{structure.id}_Card");
            cardObject.transform.SetParent(parent, false);
            var rect = cardObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(900f, 80f);

            var image = cardObject.AddComponent<Image>();
            image.sprite = MenuStyling.GetRoundedButtonSprite();
            image.type = Image.Type.Sliced;
            image.color = new Color(0.2f, 0.2f, 0.22f, 0.9f);

            var nameObject = new GameObject("Name");
            nameObject.transform.SetParent(cardObject.transform, false);
            var nameRect = nameObject.AddComponent<RectTransform>();
            nameRect.anchorMin = new Vector2(0f, 0.5f);
            nameRect.anchorMax = new Vector2(1f, 0.5f);
            nameRect.pivot = new Vector2(0.5f, 0.5f);
            nameRect.anchoredPosition = new Vector2(0f, 16f);
            nameRect.sizeDelta = new Vector2(-30f, 24f);

            var nameText = nameObject.AddComponent<TextMeshProUGUI>();
            nameText.text = structure.name;
            nameText.fontSize = 20f;
            nameText.alignment = TextAlignmentOptions.Center;
            nameText.color = Color.white;

            var descObject = new GameObject("Description");
            descObject.transform.SetParent(cardObject.transform, false);
            var descRect = descObject.AddComponent<RectTransform>();
            descRect.anchorMin = new Vector2(0.5f, 0.5f);
            descRect.anchorMax = new Vector2(0.5f, 0.5f);
            descRect.pivot = new Vector2(0.5f, 0.5f);
            descRect.anchoredPosition = new Vector2(0f, -14f);
            descRect.sizeDelta = new Vector2(840f, 36f);

            var descText = descObject.AddComponent<TextMeshProUGUI>();
            descText.text = structure.description;
            descText.fontSize = 14f;
            descText.alignment = TextAlignmentOptions.Center;
            descText.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkMuted : new Color(0.7f, 0.68f, 0.62f, 1f);
        }

        private void ShowBuildType(string type)
        {
            currentBuildType = type;
            for (var i = 0; i < buildTypePanels.Count; i++)
            {
                var panel = buildTypePanels[i];
                var panelName = panel.name.Replace("Panel", string.Empty);
                panel.SetActive(string.Equals(panelName, type, StringComparison.OrdinalIgnoreCase));
            }

            for (var i = 0; i < buildTypeButtons.Count; i++)
            {
                var button = buildTypeButtons[i];
                var label = button != null ? button.name.Replace("Button", string.Empty) : string.Empty;
                SetSubTabButtonState(button, string.Equals(label, type, StringComparison.OrdinalIgnoreCase));
            }
        }

        private void SetSubTabButtonState(Button button, bool isActive)
        {
            if (button == null)
            {
                return;
            }

            var image = button.GetComponent<Image>();
            if (image != null)
            {
                image.color = isActive ? Color.white : new Color(0.85f, 0.8f, 0.72f, 0.85f);
            }
        }

        private void RefreshSkillsTabVisibility()
        {
            var isAvailable = IsSkillsTabAvailable();
            if (combinedSkillsTabButton != null)
            {
                combinedSkillsTabButton.gameObject.SetActive(isAvailable);
            }

            if (combinedSkillsTab != null && combinedTab == CombinedTab.Skills)
            {
                combinedSkillsTab.SetActive(isAvailable);
            }

            if (!isAvailable && combinedTab == CombinedTab.Skills)
            {
                ShowCombinedTab(CombinedTab.Inventory);
            }
        }

        private bool IsSkillsTabAvailable()
        {
            var playerClass = GameState.Instance != null ? GameState.Instance.CurrentSave?.player?.characterClass ?? CharacterClass.Unknown : CharacterClass.Unknown;
            if (playerClass != CharacterClass.Unknown)
            {
                return true;
            }

            var characterClass = GameState.Instance != null ? GameState.Instance.CurrentSave?.character?.characterClass ?? CharacterClass.Unknown : CharacterClass.Unknown;
            return characterClass != CharacterClass.Unknown;
        }

        private List<BuildableStructureDefinition> LoadBuildableStructures()
        {
            var asset = Resources.Load<TextAsset>("Prefabs/Objects/buildable_structures");
            if (asset == null)
            {
                return new List<BuildableStructureDefinition>();
            }

            var parsed = JsonUtility.FromJson<BuildableStructureList>(asset.text);
            return parsed?.structures ?? new List<BuildableStructureDefinition>();
        }

        private void CreatePanelTitle(Transform parent, string title)
        {
            var titleObject = new GameObject("Title");
            titleObject.transform.SetParent(parent, false);
            var rect = titleObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 1f);
            rect.anchorMax = new Vector2(0.5f, 1f);
            rect.pivot = new Vector2(0.5f, 1f);
            rect.anchoredPosition = new Vector2(0f, -24f);
            rect.sizeDelta = new Vector2(600f, 40f);

            var text = titleObject.AddComponent<TextMeshProUGUI>();
            text.text = title;
            text.fontSize = 32f;
            text.alignment = TextAlignmentOptions.Center;
            text.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : new Color(0.15f, 0.1f, 0.05f, 1f);
        }

        private void CreateCloseButton(Transform parent, UnityEngine.Events.UnityAction onClick, Vector2? offset = null, TextAnchor alignment = TextAnchor.UpperRight)
        {
            var buttonObject = new GameObject("CloseButton");
            buttonObject.transform.SetParent(parent, false);
            var rect = buttonObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(42f, 30f);

            if (alignment == TextAnchor.UpperRight)
            {
                rect.anchorMin = new Vector2(1f, 1f);
                rect.anchorMax = new Vector2(1f, 1f);
                rect.pivot = new Vector2(1f, 1f);
                rect.anchoredPosition = offset ?? new Vector2(-24f, -18f);
            }
            else
            {
                rect.anchorMin = new Vector2(0.5f, 0f);
                rect.anchorMax = new Vector2(0.5f, 0f);
                rect.pivot = new Vector2(0.5f, 0f);
                rect.anchoredPosition = offset ?? new Vector2(0f, 16f);
            }

            var image = buttonObject.AddComponent<Image>();
            image.color = new Color(0.7f, 0.2f, 0.1f, 1f);
            image.sprite = MenuStyling.GetRoundedButtonSprite();
            image.type = Image.Type.Sliced;

            var button = buttonObject.AddComponent<Button>();
            button.onClick.AddListener(onClick);

            var labelObject = new GameObject("Label");
            labelObject.transform.SetParent(buttonObject.transform, false);
            var labelRect = labelObject.AddComponent<RectTransform>();
            labelRect.anchorMin = Vector2.zero;
            labelRect.anchorMax = Vector2.one;
            labelRect.offsetMin = Vector2.zero;
            labelRect.offsetMax = Vector2.zero;

            var text = labelObject.AddComponent<TextMeshProUGUI>();
            text.text = "X";
            text.fontSize = 20f;
            text.alignment = TextAlignmentOptions.Center;
            text.color = Color.white;
        }

        private TextMeshProUGUI CreatePanelTitleText(Transform parent, string title)
        {
            var titleObject = new GameObject("Title");
            titleObject.transform.SetParent(parent, false);
            var rect = titleObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 1f);
            rect.anchorMax = new Vector2(0.5f, 1f);
            rect.pivot = new Vector2(0.5f, 1f);
            rect.anchoredPosition = new Vector2(0f, -24f);
            rect.sizeDelta = new Vector2(600f, 40f);

            var text = titleObject.AddComponent<TextMeshProUGUI>();
            text.text = title;
            text.fontSize = 32f;
            text.alignment = TextAlignmentOptions.Center;
            text.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : new Color(0.15f, 0.1f, 0.05f, 1f);
            return text;
        }

        private Button CreateCloseButtonWithResult(Transform parent, UnityEngine.Events.UnityAction onClick, Vector2? offset = null, TextAnchor alignment = TextAnchor.UpperRight)
        {
            var buttonObject = new GameObject("CloseButton");
            buttonObject.transform.SetParent(parent, false);
            var rect = buttonObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(42f, 30f);

            if (alignment == TextAnchor.UpperRight)
            {
                rect.anchorMin = new Vector2(1f, 1f);
                rect.anchorMax = new Vector2(1f, 1f);
                rect.pivot = new Vector2(1f, 1f);
                rect.anchoredPosition = offset ?? new Vector2(-24f, -18f);
            }
            else
            {
                rect.anchorMin = new Vector2(0.5f, 0f);
                rect.anchorMax = new Vector2(0.5f, 0f);
                rect.pivot = new Vector2(0.5f, 0f);
                rect.anchoredPosition = offset ?? new Vector2(0f, 16f);
            }

            var image = buttonObject.AddComponent<Image>();
            image.color = new Color(0.7f, 0.2f, 0.1f, 1f);
            image.sprite = MenuStyling.GetRoundedButtonSprite();
            image.type = Image.Type.Sliced;

            var button = buttonObject.AddComponent<Button>();
            button.onClick.AddListener(onClick);

            var labelObject = new GameObject("Label");
            labelObject.transform.SetParent(buttonObject.transform, false);
            var labelRect = labelObject.AddComponent<RectTransform>();
            labelRect.anchorMin = Vector2.zero;
            labelRect.anchorMax = Vector2.one;
            labelRect.offsetMin = Vector2.zero;
            labelRect.offsetMax = Vector2.zero;

            var text = labelObject.AddComponent<TextMeshProUGUI>();
            text.text = "X";
            text.fontSize = 20f;
            text.alignment = TextAlignmentOptions.Center;
            text.color = Color.white;
            return button;
        }

        private void CreateTabRow(Transform parent, string[] labels)
        {
            var rowObject = new GameObject("TabRow");
            rowObject.transform.SetParent(parent, false);
            var rect = rowObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 1f);
            rect.anchorMax = new Vector2(0.5f, 1f);
            rect.pivot = new Vector2(0.5f, 1f);
            rect.anchoredPosition = new Vector2(0f, -80f);
            rect.sizeDelta = new Vector2(700f, 44f);

            var layout = rowObject.AddComponent<HorizontalLayoutGroup>();
            layout.spacing = 12f;
            layout.childControlWidth = false;
            layout.childControlHeight = true;
            layout.childForceExpandWidth = false;

            foreach (var label in labels)
            {
                var button = MenuStyling.CreateBookButton(rowObject.transform, label, new Vector2(140f, 40f));
                var text = button.GetComponentInChildren<TextMeshProUGUI>();
                if (text != null)
                {
                    text.fontSize = 18f;
                }
            }
        }

        private void CreatePlaceholderText(Transform parent, string message)
        {
            var textObject = new GameObject("PlaceholderText");
            textObject.transform.SetParent(parent, false);
            var rect = textObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = new Vector2(0f, -30f);
            rect.sizeDelta = new Vector2(700f, 120f);

            var text = textObject.AddComponent<TextMeshProUGUI>();
            text.text = message;
            text.fontSize = 20f;
            text.alignment = TextAlignmentOptions.Center;
            text.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkMuted : new Color(0.35f, 0.28f, 0.22f, 1f);
        }

        private RectTransform CreateSettingsContentRoot(Transform parent)
        {
            var contentObject = new GameObject("SettingsContent");
            contentObject.transform.SetParent(parent, false);
            var rect = contentObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = new Vector2(0f, -20f);
            rect.sizeDelta = new Vector2(520f, 0f);

            var fitter = contentObject.AddComponent<ContentSizeFitter>();
            fitter.horizontalFit = ContentSizeFitter.FitMode.Unconstrained;
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            return rect;
        }

        private void ShowSettingsView(SettingsView view)
        {
            settingsView = view;
            ClearSettingsContent();

            switch (view)
            {
                case SettingsView.Main:
                    BuildSettingsMain();
                    break;
                case SettingsView.SaveSlots:
                    BuildSaveSlotSelection();
                    break;
                case SettingsView.LoadSlots:
                    BuildLoadSlotSelection();
                    break;
            }
        }

        private void ClearSettingsContent()
        {
            if (settingsContentRoot == null)
            {
                return;
            }

            for (var i = settingsContentRoot.childCount - 1; i >= 0; i--)
            {
                Destroy(settingsContentRoot.GetChild(i).gameObject);
            }
        }

        private Transform CreateSettingsStack(string name, Vector2 size, float spacing)
        {
            var stackObject = new GameObject(name);
            stackObject.transform.SetParent(settingsContentRoot, false);
            var rect = stackObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = Vector2.zero;
            rect.sizeDelta = new Vector2(size.x, 0f);

            var layout = stackObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = spacing;
            layout.childAlignment = TextAnchor.MiddleCenter;
            layout.childControlWidth = false;
            layout.childControlHeight = false;
            layout.childForceExpandWidth = false;
            layout.childForceExpandHeight = false;

            var fitter = stackObject.AddComponent<ContentSizeFitter>();
            fitter.horizontalFit = ContentSizeFitter.FitMode.Unconstrained;
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;

            return stackObject.transform;
        }

        private void CreateSettingsHeaderText(Transform parent, string text)
        {
            var headerObject = new GameObject("SettingsHeader");
            headerObject.transform.SetParent(parent, false);
            var tmp = headerObject.AddComponent<TextMeshProUGUI>();
            tmp.text = text;
            tmp.fontSize = 26f;
            tmp.alignment = TextAlignmentOptions.Center;
            tmp.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : new Color(0.18f, 0.12f, 0.08f, 1f);

            var layout = headerObject.AddComponent<LayoutElement>();
            layout.preferredHeight = 30f;
        }

        private Button CreateSettingsActionButton(Transform parent, string label, UnityEngine.Events.UnityAction onClick, Vector2? size = null, bool useRounded = false)
        {
            var resolvedSize = size ?? new Vector2(260f, 52f);
            var button = MenuStyling.CreateBookButton(parent, label, resolvedSize, $"{label}Button");
            button.onClick.RemoveAllListeners();
            button.onClick.AddListener(onClick);

            if (useRounded)
            {
                var image = button.GetComponent<Image>();
                if (image != null)
                {
                    image.sprite = MenuStyling.GetRoundedButtonSprite();
                    image.type = Image.Type.Sliced;
                }
            }

            var text = button.GetComponentInChildren<TextMeshProUGUI>();
            if (text != null)
            {
                text.fontSize = 22f;
                text.color = Color.white;
            }

            return button;
        }

        private void BuildSettingsMain()
        {
            var stack = CreateSettingsStack("SettingsActions", new Vector2(320f, 220f), 16f);
            CreateSettingsActionButton(stack, "Save Game", () => ShowSettingsView(SettingsView.SaveSlots));
            CreateSettingsActionButton(stack, "Load Game", () => ShowSettingsView(SettingsView.LoadSlots));
            CreateSettingsActionButton(stack, "Main Menu", ReturnToMainMenu);
        }

        private void BuildSaveSlotSelection()
        {
            var stack = CreateSettingsStack("SaveSlotActions", new Vector2(380f, 260f), 10f);
            CreateSettingsHeaderText(stack, "Save Game");

            var characterIndex = GetCurrentCharacterIndex();
            for (var i = 0; i < MaxSaveSlotsPerCharacter; i++)
            {
                var slotIndex = i;
                var label = GetSaveSlotLabel(characterIndex, slotIndex, true);
                CreateSettingsActionButton(stack, label, () => SaveToSlot(slotIndex), new Vector2(4500f, 44f), true);
            }

            CreateSettingsActionButton(stack, "Back", () => ShowSettingsView(SettingsView.Main), new Vector2(160f, 44f), true);
        }

        private void BuildLoadSlotSelection()
        {
            var stack = CreateSettingsStack("LoadSlotActions", new Vector2(380f, 260f), 10f);
            CreateSettingsHeaderText(stack, "Load Game");

            var characterIndex = GetCurrentCharacterIndex();
            var hasAny = false;
            for (var i = 0; i < MaxSaveSlotsPerCharacter; i++)
            {
                if (!SaveSlotHasData(characterIndex, i))
                {
                    continue;
                }

                hasAny = true;
                var slotIndex = i;
                var label = GetSaveSlotLabel(characterIndex, slotIndex, false);
                CreateSettingsActionButton(stack, label, () => LoadFromSlot(slotIndex), new Vector2(380f, 44f), true);
            }

            if (!hasAny)
            {
                CreateSettingsHeaderText(stack, "No saved games found.");
            }

            CreateSettingsActionButton(stack, "Back", () => ShowSettingsView(SettingsView.Main), new Vector2(160f, 44f), true);
        }

        private void CreateInventoryGrid(Transform parent, Vector2 size, int columns, int rows)
        {
            var gridObject = new GameObject("InventoryGrid");
            gridObject.transform.SetParent(parent, false);
            var rect = gridObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = Vector2.zero;
            rect.sizeDelta = size;

            var grid = gridObject.AddComponent<GridLayoutGroup>();
            grid.cellSize = new Vector2(60f, 60f);
            grid.spacing = new Vector2(8f, 8f);
            grid.constraint = GridLayoutGroup.Constraint.FixedColumnCount;
            grid.constraintCount = Mathf.Max(1, columns);

            var slotCount = Mathf.Max(1, columns) * Mathf.Max(1, rows);
            for (var i = 0; i < slotCount; i++)
            {
                var slot = new GameObject($"Slot_{i + 1}");
                slot.transform.SetParent(gridObject.transform, false);
                var image = slot.AddComponent<Image>();
                image.color = new Color(0.25f, 0.25f, 0.28f, 1f);
            }
        }

        private void TogglePanel(GameObject panel)
        {
            if (panel == null)
            {
                return;
            }

            var show = !panel.activeSelf;
            HideAllPanels();
            panel.SetActive(show);
            if (show && panel == settingsPanel)
            {
                ShowSettingsView(SettingsView.Main);
            }
            if (show && panel == combinedPanel)
            {
                RefreshSkillsTabVisibility();
                ShowCombinedTab(combinedTab);
                if (combinedTab == CombinedTab.Inventory)
                {
                    RefreshInventoryUI();
                }
            }
        }

        private void HideAllPanels()
        {
            if (combinedPanel != null) combinedPanel.SetActive(false);
            if (settingsPanel != null) settingsPanel.SetActive(false);
            if (chestPanel != null) chestPanel.SetActive(false);
            if (companionPanel != null) companionPanel.SetActive(false);
            if (battlePanel != null) battlePanel.SetActive(false);
            if (itemActionPanel != null) itemActionPanel.SetActive(false);
        }

        public void OpenChest(ChestInstance chest)
        {
            if (chest == null || chestPanel == null)
            {
                return;
            }

            activeChest = chest;
            activeChest.SetOpen(true);
            Debug.Log($"[ChestUI] OpenChest {activeChest.ChestId} items {activeChest.Items?.Count ?? 0}");
            if (chestTitle != null)
            {
                chestTitle.text = activeChest.DisplayName ?? "Chest";
            }

            RefreshChestItems();
            HideAllPanels();
            chestPanel.SetActive(true);
            chestPanel.transform.SetAsLastSibling();
        }

        public void CloseChestIfOpen()
        {
            if (chestPanel != null && chestPanel.activeSelf)
            {
                chestPanel.SetActive(false);
            }

            if (activeChest != null)
            {
                activeChest.SetOpen(false);
                activeChest = null;
            }
        }

        private void CloseChest()
        {
            CloseChestIfOpen();
        }

        public bool IsChestOpen => chestPanel != null && chestPanel.activeSelf;

        public void OpenCompanion(CompanionInstance companion)
        {
            if (companion == null || companionPanel == null)
            {
                return;
            }

            activeCompanion = companion;
            if (companionTitle != null)
            {
                companionTitle.text = companion.DisplayName;
            }

            var requirement = companion.RequiredBefriendingItem;
            if (string.IsNullOrWhiteSpace(requirement))
            {
                companionBody.text = $"{companion.DisplayName} seems friendly. You can befriend them right away.";
            }
            else
            {
                companionBody.text = $"{companion.DisplayName} will join you if you bring: {requirement}.";
            }

            UpdateCompanionBefriendState();
            HideAllPanels();
            companionPanel.SetActive(true);
            companionPanel.transform.SetAsLastSibling();
        }

        private void UpdateCompanionBefriendState()
        {
            if (companionBefriendButton == null || activeCompanion == null)
            {
                return;
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            var canAdd = player != null && player.CanAddCompanion();
            var requirement = activeCompanion.RequiredBefriendingItem;
            var hasRequirement = string.IsNullOrWhiteSpace(requirement) || HasInventoryItem(requirement);
            companionBefriendButton.interactable = canAdd && hasRequirement;
        }

        private void TryBefriendActiveCompanion()
        {
            if (activeCompanion == null)
            {
                return;
            }

            var requirement = activeCompanion.RequiredBefriendingItem;
            if (!string.IsNullOrWhiteSpace(requirement) && !HasInventoryItem(requirement))
            {
                return;
            }

            if (!string.IsNullOrWhiteSpace(requirement))
            {
                RemoveItemById(requirement);
            }

            var scene = FindFirstObjectByType<GameSceneController>();
            if (scene != null && scene.TryAddCompanionToParty(activeCompanion))
            {
                RefreshCompanionsTab();
                CloseCompanionPanel();
            }
        }

        private void CloseCompanionPanel()
        {
            if (companionPanel != null)
            {
                companionPanel.SetActive(false);
            }

            activeCompanion = null;
        }

        public void OpenBattle(List<EnemyInstance> enemies, EnemyInstance primaryEnemy)
        {
            if (battlePanel == null || enemies == null || enemies.Count == 0)
            {
                return;
            }

            activeEnemies.Clear();
            activeEnemies.AddRange(enemies);
            activeEnemy = primaryEnemy ?? enemies[0];
            var scene = FindFirstObjectByType<GameSceneController>();
            scene?.BeginBattleEncounter(activeEnemies, activeEnemy);
            RefreshBattlePanel();
            HideAllPanels();
            battlePanel.SetActive(true);
            battlePanel.transform.SetAsLastSibling();
        }

        private void CloseBattlePanel()
        {
            if (battlePanel != null)
            {
                battlePanel.SetActive(false);
            }

            if (activeEnemy != null)
            {
                var scene = FindFirstObjectByType<GameSceneController>();
                scene?.EndBattleEncounter(activeEnemies);
                activeEnemy = null;
            }

            activeEnemies.Clear();
            battleEnemyStatus.Clear();
            battleTargetEnemy = null;
            battlePartyActors.Clear();
            battleActorStatus.Clear();
            battleActorsActed.Clear();
            selectedBattleActor = null;
        }

        private void RefreshBattlePanel()
        {
            if (battleLeftRoot == null || battleRightRoot == null)
            {
                return;
            }

            for (var i = battleRightRoot.childCount - 1; i >= 0; i--)
            {
                Destroy(battleRightRoot.GetChild(i).gameObject);
            }

            if (battleActionsRoot != null)
            {
                for (var i = battleActionsRoot.childCount - 1; i >= 0; i--)
                {
                    Destroy(battleActionsRoot.GetChild(i).gameObject);
                }
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player != null)
            {
                battlePlayerHp = Mathf.Max(1, player.hitPoints);
                BuildBattlePartyActors(player);
                UpdateBattleActorHighlight();
                RefreshBattleActionsForActor(selectedBattleActor);
            }

            if (activeEnemy != null)
            {
                battleEnemyStatus.Clear();
                battleTargetEnemy = activeEnemy;
                for (var i = 0; i < activeEnemies.Count; i++)
                {
                    var enemy = activeEnemies[i];
                    if (enemy == null)
                    {
                        continue;
                    }

                    var baseHp = enemy.Definition != null ? enemy.Definition.hitPoints : 10;
                    var status = new BattleEnemyStatus
                    {
                        enemy = enemy,
                        maxHp = Mathf.Max(1, baseHp),
                        hp = Mathf.Max(1, baseHp)
                    };
                    status.label = CreateBattleEnemyEntry(battleRightRoot, enemy.DisplayName, status.hp, status.maxHp, enemy, out var hpFill);
                    status.hpFill = hpFill;
                    battleEnemyStatus[enemy] = status;
                }
            }

            battleEnemyStunTurns = 0;
            battleEnemyAttackModifier = 0;
            battleEnemyAttackDebuffTurns = 0;
            battleEnemyBurnDamage = 0;
            battleEnemyBurnTurns = 0;
            UpdateBattleTargetHighlight();
        }

        private TextMeshProUGUI CreateBattleEntry(Transform parent, string label, int value)
        {
            if (parent == null)
            {
                return null;
            }

            var entryObject = new GameObject("Entry");
            entryObject.transform.SetParent(parent, false);
            var rect = entryObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(320f, 76f);

            var text = entryObject.AddComponent<TextMeshProUGUI>();
            text.text = $"{label}  HP {value}";
            text.fontSize = 18f;
            text.alignment = TextAlignmentOptions.Left;
            text.color = new Color(0.92f, 0.88f, 0.8f, 1f);
            return text;
        }

        private TextMeshProUGUI CreateBattleEnemyEntry(Transform parent, string label, int value, int maxValue, EnemyInstance enemy, out Image hpFill)
        {
            hpFill = null;
            if (parent == null)
            {
                return null;
            }

            var entryObject = new GameObject("EnemyEntry");
            entryObject.transform.SetParent(parent, false);
            var rect = entryObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(320f, 76f);

            var image = entryObject.AddComponent<Image>();
            image.color = new Color(0.35f, 0.2f, 0.2f, 0.6f);
            image.sprite = MenuStyling.GetRoundedButtonSprite();
            image.type = Image.Type.Sliced;

            var button = entryObject.AddComponent<Button>();
            button.onClick.AddListener(() =>
            {
                battleTargetEnemy = enemy;
                UpdateBattleTargetHighlight();
            });

            var portraitObject = new GameObject("Portrait");
            portraitObject.transform.SetParent(entryObject.transform, false);
            var portraitRect = portraitObject.AddComponent<RectTransform>();
            portraitRect.anchorMin = new Vector2(0f, 0.5f);
            portraitRect.anchorMax = new Vector2(0f, 0.5f);
            portraitRect.pivot = new Vector2(0f, 0.5f);
            portraitRect.anchoredPosition = new Vector2(8f, 8f);
            portraitRect.sizeDelta = new Vector2(44f, 44f);
            var portraitImage = portraitObject.AddComponent<Image>();
            portraitImage.sprite = GetSolidSprite();
            portraitImage.color = new Color(0.55f, 0.35f, 0.35f, 0.9f);

            var textObject = new GameObject("Label");
            textObject.transform.SetParent(entryObject.transform, false);
            var textRect = textObject.AddComponent<RectTransform>();
            textRect.anchorMin = new Vector2(0f, 1f);
            textRect.anchorMax = new Vector2(1f, 1f);
            textRect.pivot = new Vector2(0.5f, 1f);
            textRect.anchoredPosition = new Vector2(0f, -6f);
            textRect.sizeDelta = new Vector2(-72f, 24f);

            var text = textObject.AddComponent<TextMeshProUGUI>();
            text.text = $"{label}  HP {value}";
            text.fontSize = 16f;
            text.alignment = TextAlignmentOptions.Left;
            text.color = new Color(0.92f, 0.88f, 0.8f, 1f);

            hpFill = CreateInlineBar(entryObject.transform, new Vector2(240f, 10f), new Color(0.2f, 0.85f, 0.2f, 1f), out _);
            hpFill.transform.localPosition = new Vector3(20f, -22f, 0f);
            hpFill.fillAmount = maxValue > 0 ? Mathf.Clamp01((float)value / maxValue) : 0f;

            if (enemy != null && battleEnemyStatus.TryGetValue(enemy, out var status))
            {
                status.button = button;
                status.background = image;
            }
            else if (enemy != null)
            {
                battleEnemyStatus[enemy] = new BattleEnemyStatus
                {
                    enemy = enemy,
                    button = button,
                    background = image,
                    label = text,
                    hp = value,
                    maxHp = maxValue,
                    hpFill = hpFill
                };
            }
            return text;
        }

        private void UpdateBattleTargetHighlight()
        {
            foreach (var entry in battleEnemyStatus.Values)
            {
                if (entry == null || entry.background == null)
                {
                    continue;
                }

                entry.background.color = entry.enemy == battleTargetEnemy
                    ? new Color(0.55f, 0.25f, 0.25f, 0.85f)
                    : new Color(0.35f, 0.2f, 0.2f, 0.6f);
            }
        }

        private void SelectBattleActorByKey(string key)
        {
            if (string.IsNullOrWhiteSpace(key) || battlePanel == null || !battlePanel.activeSelf)
            {
                return;
            }

            for (var i = 0; i < battlePartyActors.Count; i++)
            {
                if (string.Equals(battlePartyActors[i].key, key, StringComparison.OrdinalIgnoreCase))
                {
                    selectedBattleActor = battlePartyActors[i];
                    UpdateBattleActorHighlight();
                    RefreshBattleActionsForActor(selectedBattleActor);
                    return;
                }
            }
        }

        private void BuildBattlePartyActors(Player player)
        {
            battlePartyActors.Clear();
            battleActorStatus.Clear();
            battleActorsActed.Clear();

            if (player == null)
            {
                return;
            }

            var playerActor = new BattleActor
            {
                key = "player",
                kind = BattleActorKind.Player,
                name = $"{player.name} (You)",
                level = player.level,
                skillIds = GetPlayerSkillIds(player)
            };
            battlePartyActors.Add(playerActor);

            if (player.companions != null)
            {
                for (var i = 0; i < player.companions.Count; i++)
                {
                    var companion = player.companions[i];
                    if (companion == null)
                    {
                        continue;
                    }

                    var skillIds = GetCompanionSkillIds(companion.id);
                    battlePartyActors.Add(new BattleActor
                    {
                        key = $"companion_{i}_{companion.id}",
                        kind = BattleActorKind.Companion,
                        name = !string.IsNullOrWhiteSpace(companion.name) ? companion.name : companion.id,
                        level = companion.level,
                        skillIds = skillIds
                    });
                }
            }

            selectedBattleActor = battlePartyActors.Count > 0 ? battlePartyActors[0] : null;
        }

        private void RenderBattlePartyEntries()
        {
            if (battleLeftRoot == null)
            {
                return;
            }

            for (var i = battleLeftRoot.childCount - 1; i >= 0; i--)
            {
                Destroy(battleLeftRoot.GetChild(i).gameObject);
            }

            foreach (var actor in battlePartyActors)
            {
                var entry = CreateBattlePartyEntry(battleLeftRoot, actor);
                battleActorStatus[actor.key] = entry;
            }

            UpdateBattleActorHighlight();
            RefreshBattleActionsForActor(selectedBattleActor);
        }

        private BattleActorStatus CreateBattlePartyEntry(Transform parent, BattleActor actor)
        {
            var entryObject = new GameObject($"{actor.key}_Entry");
            entryObject.transform.SetParent(parent, false);
            var rect = entryObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(320f, 36f);

            var image = entryObject.AddComponent<Image>();
            image.color = new Color(0.2f, 0.25f, 0.35f, 0.6f);
            image.sprite = MenuStyling.GetRoundedButtonSprite();
            image.type = Image.Type.Sliced;

            var button = entryObject.AddComponent<Button>();
            button.onClick.AddListener(() =>
            {
                selectedBattleActor = actor;
                UpdateBattleActorHighlight();
                RefreshBattleActionsForActor(actor);
            });

            var portraitObject = new GameObject("Portrait");
            portraitObject.transform.SetParent(entryObject.transform, false);
            var portraitRect = portraitObject.AddComponent<RectTransform>();
            portraitRect.anchorMin = new Vector2(0f, 0.5f);
            portraitRect.anchorMax = new Vector2(0f, 0.5f);
            portraitRect.pivot = new Vector2(0f, 0.5f);
            portraitRect.anchoredPosition = new Vector2(8f, 8f);
            portraitRect.sizeDelta = new Vector2(44f, 44f);
            var portraitImage = portraitObject.AddComponent<Image>();
            portraitImage.sprite = GetSolidSprite();
            portraitImage.color = new Color(0.35f, 0.45f, 0.6f, 0.9f);

            var textObject = new GameObject("Label");
            textObject.transform.SetParent(entryObject.transform, false);
            var textRect = textObject.AddComponent<RectTransform>();
            textRect.anchorMin = new Vector2(0f, 1f);
            textRect.anchorMax = new Vector2(1f, 1f);
            textRect.pivot = new Vector2(0.5f, 1f);
            textRect.anchoredPosition = new Vector2(0f, -6f);
            textRect.sizeDelta = new Vector2(-72f, 24f);

            var text = textObject.AddComponent<TextMeshProUGUI>();
            text.text = actor.kind == BattleActorKind.Player
                ? $"{actor.name}  HP {battlePlayerHp}"
                : actor.name;
            text.fontSize = 16f;
            text.alignment = TextAlignmentOptions.Left;
            text.color = new Color(0.92f, 0.88f, 0.8f, 1f);

            var status = new BattleActorStatus
            {
                actor = actor,
                button = button,
                background = image,
                label = text
            };
            if (actor.kind == BattleActorKind.Player)
            {
                battlePlayerEntry = text;
            }

            var hpFill = CreateInlineBar(entryObject.transform, new Vector2(240f, 10f), new Color(0.2f, 0.85f, 0.2f, 1f), out _);
            hpFill.transform.localPosition = new Vector3(20f, -22f, 0f);
            var maxHp = actor.kind == BattleActorKind.Player
                ? Mathf.Max(1, (GameState.Instance?.CurrentSave?.player?.maxHitPoints ?? battlePlayerHp))
                : Mathf.Max(1, GetCompanionMaxHp(actor));
            hpFill.fillAmount = maxHp > 0 ? Mathf.Clamp01((float)battlePlayerHp / maxHp) : 0f;
            status.hpFill = hpFill;

            if (actor.kind == BattleActorKind.Player)
            {
                var resourceFill = CreateInlineBar(entryObject.transform, new Vector2(240f, 10f), new Color(0.25f, 0.55f, 0.95f, 1f), out _);
                resourceFill.transform.localPosition = new Vector3(20f, -36f, 0f);
                var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
                var maxMana = player != null && player.maxMana > 0 ? player.maxMana : (player?.mana ?? 0);
                resourceFill.fillAmount = maxMana > 0 ? Mathf.Clamp01((float)player.mana / maxMana) : 0f;
                status.resourceFill = resourceFill;
            }

            return status;
        }

        private void RefreshBattleActionsForActor(BattleActor actor)
        {
            if (battleActionsRoot == null)
            {
                return;
            }

            for (var i = battleActionsRoot.childCount - 1; i >= 0; i--)
            {
                Destroy(battleActionsRoot.GetChild(i).gameObject);
            }

            if (actor == null)
            {
                return;
            }

            var actions = GetBattleActionsForActor(actor);
            RenderActionBarSlots(actor, actions);
        }

        private void RefreshActionBarForCurrentActor()
        {
            if (battlePanel != null && battlePanel.activeSelf)
            {
                RefreshBattleActionsForActor(selectedBattleActor);
                return;
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null)
            {
                return;
            }

            var actor = new BattleActor
            {
                key = "player",
                kind = BattleActorKind.Player,
                name = $"{player.name} (You)",
                level = player.level,
                skillIds = GetPlayerSkillIds(player)
            };
            var actions = GetBattleActionsForActor(actor);
            RenderActionBarSlots(actor, actions);
        }

        private void RenderActionBarSlots(BattleActor actor, List<BattleAction> defaultActions)
        {
            if (actionBarGrid == null || actor == null)
            {
                return;
            }

            for (var i = actionBarGrid.transform.childCount - 1; i >= 0; i--)
            {
                Destroy(actionBarGrid.transform.GetChild(i).gameObject);
            }

            var slots = GetActionBarAssignments(actor.key, defaultActions);
            var visibleSlots = actionBarExpanded ? 40 : 10;

            for (var i = 0; i < visibleSlots; i++)
            {
                var slotObject = new GameObject($"Slot_{i + 1}");
                slotObject.transform.SetParent(actionBarGrid.transform, false);
                var image = slotObject.AddComponent<Image>();
                image.sprite = GetSolidSprite();
                image.color = new Color(0.08f, 0.08f, 0.1f, 0.9f);

                var dropTarget = slotObject.AddComponent<ActionBarSlotDropTarget>();
                dropTarget.ui = this;
                dropTarget.actorKey = actor.key;
                dropTarget.slotIndex = i;

                var action = slots.Count > i ? slots[i] : null;
                if (action != null)
                {
                    CreateActionBarButton(slotObject.transform, actor.key, i, action);
                }
            }
        }

        private List<BattleAction> GetActionBarAssignments(string actorKey, List<BattleAction> defaults)
        {
            if (string.IsNullOrWhiteSpace(actorKey))
            {
                actorKey = "player";
            }

            if (!actionBarAssignments.TryGetValue(actorKey, out var slots))
            {
                slots = new List<BattleAction>();
                for (var i = 0; i < 40; i++)
                {
                    slots.Add(null);
                }

                actionBarAssignments[actorKey] = slots;
            }

            var hasAny = false;
            for (var i = 0; i < slots.Count; i++)
            {
                if (slots[i] != null)
                {
                    hasAny = true;
                    break;
                }
            }

            if (!hasAny && defaults != null)
            {
                for (var i = 0; i < defaults.Count && i < slots.Count; i++)
                {
                    slots[i] = defaults[i];
                }
            }

            return slots;
        }

        private void CreateActionBarButton(Transform parent, string actorKey, int slotIndex, BattleAction action)
        {
            var buttonObject = new GameObject($"{action.id}_Action");
            buttonObject.transform.SetParent(parent, false);
            var rect = buttonObject.AddComponent<RectTransform>();
            rect.anchorMin = Vector2.zero;
            rect.anchorMax = Vector2.one;
            rect.offsetMin = new Vector2(2f, 2f);
            rect.offsetMax = new Vector2(-2f, -2f);

            var image = buttonObject.AddComponent<Image>();
            image.sprite = GetSolidSprite();
            image.color = new Color(0.16f, 0.16f, 0.2f, 0.95f);

            var button = buttonObject.AddComponent<Button>();
            button.onClick.AddListener(() => ResolveBattleAction(action));

            var labelObject = new GameObject("Label");
            labelObject.transform.SetParent(buttonObject.transform, false);
            var labelRect = labelObject.AddComponent<RectTransform>();
            labelRect.anchorMin = Vector2.zero;
            labelRect.anchorMax = Vector2.one;
            labelRect.offsetMin = Vector2.zero;
            labelRect.offsetMax = Vector2.zero;
            var text = labelObject.AddComponent<TextMeshProUGUI>();
            text.text = action.label;
            text.fontSize = 12f;
            text.alignment = TextAlignmentOptions.Center;
            text.color = new Color(0.92f, 0.88f, 0.8f, 1f);

            var dragHandler = buttonObject.AddComponent<ActionBarActionDragHandler>();
            dragHandler.ui = this;
            dragHandler.actorKey = actorKey;
            dragHandler.slotIndex = slotIndex;
            dragHandler.action = action;
            dragHandler.rectTransform = rect;
            dragHandler.canvasGroup = buttonObject.AddComponent<CanvasGroup>();
        }

        private void MoveActionBarAction(string actorKey, int sourceIndex, int targetIndex)
        {
            if (!actionBarAssignments.TryGetValue(actorKey, out var slots))
            {
                return;
            }

            if (sourceIndex < 0 || sourceIndex >= slots.Count || targetIndex < 0 || targetIndex >= slots.Count)
            {
                return;
            }

            var temp = slots[targetIndex];
            slots[targetIndex] = slots[sourceIndex];
            slots[sourceIndex] = temp;
            RefreshActionBarForCurrentActor();
        }

        private int GetCompanionMaxHp(BattleActor actor)
        {
            if (actor == null)
            {
                return 10;
            }

            EnsureCompanionSkillDefinitionsLoaded();
            foreach (var entry in companionSkillDefinitions.Values)
            {
                if (entry != null && string.Equals(entry.name, actor.name, StringComparison.OrdinalIgnoreCase))
                {
                    return Mathf.Max(1, entry.hitPoints);
                }
            }

            return 10;
        }

        private List<BattleAction> GetBattleActionsForActor(BattleActor actor)
        {
            var result = new List<BattleAction>();
            result.Add(new BattleAction { kind = BattleActionKind.Skill, id = "Attack", label = "Attack" });

            if (actor.skillIds != null)
            {
                foreach (var skillId in actor.skillIds)
                {
                    if (!string.IsNullOrWhiteSpace(skillId))
                    {
                        var definition = GetSkillDefinition(skillId);
                        var label = !string.IsNullOrWhiteSpace(definition?.name) ? definition.name : skillId;
                        result.Add(new BattleAction { kind = BattleActionKind.Skill, id = skillId, label = label });
                    }
                }
            }

            if (actor.kind == BattleActorKind.Player)
            {
                var consumables = GetBattleConsumables();
                result.AddRange(consumables);
            }

            return result;
        }

        private void UpdateBattleActorHighlight()
        {
            foreach (var entry in battleActorStatus.Values)
            {
                if (entry == null || entry.background == null)
                {
                    continue;
                }

                var isSelected = selectedBattleActor != null && entry.actor.key == selectedBattleActor.key;
                var hasActed = battleActorsActed.Contains(entry.actor.key);
                entry.background.color = hasActed
                    ? new Color(0.2f, 0.2f, 0.2f, 0.35f)
                    : isSelected
                        ? new Color(0.25f, 0.4f, 0.55f, 0.85f)
                        : new Color(0.2f, 0.25f, 0.35f, 0.6f);
            }

            foreach (var entry in partyHudActorStatus.Values)
            {
                if (entry == null || entry.background == null)
                {
                    continue;
                }

                var isSelected = selectedBattleActor != null && entry.actor.key == selectedBattleActor.key;
                var hasActed = battleActorsActed.Contains(entry.actor.key);
                entry.background.color = hasActed
                    ? new Color(0.2f, 0.2f, 0.2f, 0.35f)
                    : isSelected
                        ? new Color(0.25f, 0.4f, 0.55f, 0.85f)
                        : new Color(0.2f, 0.25f, 0.35f, 0.6f);
            }
        }

        private bool AllBattleActorsActed()
        {
            for (var i = 0; i < battlePartyActors.Count; i++)
            {
                if (!battleActorsActed.Contains(battlePartyActors[i].key))
                {
                    return false;
                }
            }

            return true;
        }

        private void SelectNextAvailableActor()
        {
            for (var i = 0; i < battlePartyActors.Count; i++)
            {
                if (!battleActorsActed.Contains(battlePartyActors[i].key))
                {
                    selectedBattleActor = battlePartyActors[i];
                    UpdateBattleActorHighlight();
                    RefreshBattleActionsForActor(selectedBattleActor);
                    return;
                }
            }
        }

        private List<string> GetPlayerSkillIds(Player player)
        {
            var result = new List<string>();
            if (player?.learnedSkills == null)
            {
                return result;
            }

            foreach (var skillId in player.learnedSkills)
            {
                if (!string.IsNullOrWhiteSpace(skillId))
                {
                    result.Add(skillId);
                }
            }

            return result;
        }

        private List<string> GetCompanionSkillIds(string companionId)
        {
            if (string.IsNullOrWhiteSpace(companionId))
            {
                return new List<string>();
            }

            EnsureCompanionSkillDefinitionsLoaded();
            if (companionSkillDefinitions.TryGetValue(companionId, out var definition))
            {
                return definition.skillIds ?? new List<string>();
            }

            return new List<string>();
        }

        private int GetCompanionMaxHp(string companionId)
        {
            if (string.IsNullOrWhiteSpace(companionId))
            {
                return 10;
            }

            EnsureCompanionSkillDefinitionsLoaded();
            if (companionSkillDefinitions.TryGetValue(companionId, out var definition))
            {
                return Mathf.Max(1, definition.hitPoints);
            }

            return 10;
        }

        private void EnsureCompanionSkillDefinitionsLoaded()
        {
            if (companionSkillDefinitions.Count > 0)
            {
                return;
            }

            var asset = Resources.Load<TextAsset>("Prefabs/Data/companions");
            if (asset == null)
            {
                return;
            }

            var parsed = JsonUtility.FromJson<CompanionSkillList>(asset.text);
            if (parsed?.animals == null)
            {
                return;
            }

            foreach (var companion in parsed.animals)
            {
                if (companion == null || string.IsNullOrWhiteSpace(companion.id))
                {
                    continue;
                }

                companionSkillDefinitions[companion.id] = companion;
            }
        }

        private void CreateBattleActionButton(Transform parent, BattleAction action)
        {
            if (parent == null)
            {
                return;
            }

            var buttonObject = new GameObject($"{action.id}Action");
            buttonObject.transform.SetParent(parent, false);
            var rect = buttonObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(56f, 56f);
            var layout = buttonObject.AddComponent<LayoutElement>();
            layout.preferredWidth = 56f;
            layout.preferredHeight = 56f;

            var image = buttonObject.AddComponent<Image>();
            image.sprite = GetSolidSprite();
            image.color = new Color(0.12f, 0.12f, 0.16f, 0.95f);

            var button = buttonObject.AddComponent<Button>();
            button.onClick.RemoveAllListeners();
            button.onClick.AddListener(() =>
            {
                ResolveBattleAction(action);
            });

            var labelObject = new GameObject("Label");
            labelObject.transform.SetParent(buttonObject.transform, false);
            var labelRect = labelObject.AddComponent<RectTransform>();
            labelRect.anchorMin = Vector2.zero;
            labelRect.anchorMax = Vector2.one;
            labelRect.offsetMin = Vector2.zero;
            labelRect.offsetMax = Vector2.zero;
            var text = labelObject.AddComponent<TextMeshProUGUI>();
            text.text = action.label;
            text.fontSize = 12f;
            text.alignment = TextAlignmentOptions.Center;
            text.color = new Color(0.92f, 0.88f, 0.8f, 1f);
        }

        private void ResolveBattleAction(BattleAction action)
        {
            if (selectedBattleActor == null || action == null)
            {
                return;
            }

            if (battleActorsActed.Contains(selectedBattleActor.key))
            {
                return;
            }

            if (action.kind == BattleActionKind.Item)
            {
                if (selectedBattleActor.kind != BattleActorKind.Player)
                {
                    return;
                }

                UseBattleConsumable(action.id);
            }
            else
            {
                ResolveBattleTurn(selectedBattleActor, action.id);
            }

            battleActorsActed.Add(selectedBattleActor.key);
            UpdateBattleActorHighlight();

            if (AllBattleActorsActed())
            {
                ResolveEnemyTurns();
                battleActorsActed.Clear();
                SelectNextAvailableActor();
            }
        }

        private void EnsureSkillDefinitionsLoaded()
        {
            if (skillDefinitions.Count > 0)
            {
                return;
            }

            var asset = Resources.Load<TextAsset>("Prefabs/Character/skills");
            if (asset == null)
            {
                return;
            }

            var parsed = JsonUtility.FromJson<SkillList>(asset.text);
            if (parsed?.skills == null)
            {
                return;
            }

            foreach (var skill in parsed.skills)
            {
                if (skill != null && !string.IsNullOrWhiteSpace(skill.id))
                {
                    skillDefinitions[skill.id] = skill;
                }
            }
        }

        private SkillDefinition GetSkillDefinition(string skillId)
        {
            if (string.IsNullOrWhiteSpace(skillId))
            {
                return null;
            }

            EnsureSkillDefinitionsLoaded();
            if (skillDefinitions.TryGetValue(skillId, out var definition))
            {
                return definition;
            }

            return new SkillDefinition
            {
                id = skillId,
                name = skillId,
                type = string.Equals(skillId, "Defend", StringComparison.OrdinalIgnoreCase) ? "defend" : "attack",
                damageMultiplier = 1f,
                baseDamage = null
            };
        }

        private List<BattleAction> GetBattleConsumables()
        {
            var result = new List<BattleAction>();
            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || player.inventory == null)
            {
                return result;
            }

            NormalizeInventoryStacks(player.inventory);
            foreach (var item in player.inventory)
            {
                if (item == null)
                {
                    continue;
                }

                var definition = GetItemDefinition(item);
                if (definition == null || definition.consumableData == null)
                {
                    continue;
                }

                var count = Mathf.Max(1, item.quantity);
                var label = !string.IsNullOrWhiteSpace(definition.name) ? definition.name : item.id;
                result.Add(new BattleAction
                {
                    kind = BattleActionKind.Item,
                    id = item.id,
                    label = $"{label} x{count}"
                });
            }

            return result;
        }

        private void UseBattleConsumable(string itemId)
        {
            if (string.IsNullOrWhiteSpace(itemId))
            {
                return;
            }

            var definition = GetItemDefinition(new Item { id = itemId });
            if (definition == null || definition.consumableData == null)
            {
                return;
            }

            var effectType = definition.consumableData.effectType;
            var effectValue = definition.consumableData.effectValue;
            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null)
            {
                return;
            }

            if (string.Equals(effectType, "heal", StringComparison.OrdinalIgnoreCase))
            {
                player.hitPoints = Mathf.Min(player.maxHitPoints > 0 ? player.maxHitPoints : player.hitPoints + effectValue, player.hitPoints + effectValue);
                battlePlayerHp = player.hitPoints;
                if (battlePlayerEntry != null)
                {
                    battlePlayerEntry.text = $"{player.name} (You)  HP {battlePlayerHp}";
                }
            }
            else if (string.Equals(effectType, "restoreMana", StringComparison.OrdinalIgnoreCase))
            {
                player.mana = Mathf.Min(player.maxMana > 0 ? player.maxMana : player.mana + effectValue, player.mana + effectValue);
            }

            RemoveItemById(itemId);
            RefreshBattlePanel();
        }

        private void ResolveBattleTurn(BattleActor actor, string skillId)
        {
            if (activeEnemy == null)
            {
                return;
            }

            if (actor == null)
            {
                return;
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null)
            {
                return;
            }

            if (battleTargetEnemy == null)
            {
                if (activeEnemies.Count > 0)
                {
                    battleTargetEnemy = activeEnemies[0];
                }
                else
                {
                    return;
                }
            }

            if (!battleEnemyStatus.TryGetValue(battleTargetEnemy, out var targetStatus))
            {
                return;
            }

            var skill = GetSkillDefinition(skillId);
            var isDefend = string.Equals(skillId, "Defend", StringComparison.OrdinalIgnoreCase);
            var baseDamage = Mathf.Max(1, 3 + Mathf.Max(0, actor.level / 2));
            var damageMultiplier = skill != null && skill.damageMultiplier.HasValue ? skill.damageMultiplier.Value : 1f;
            var flatDamage = skill != null && skill.baseDamage.HasValue ? skill.baseDamage.Value : 0f;
            var playerDamage = skill != null && string.Equals(skill.type, "attack", StringComparison.OrdinalIgnoreCase)
                ? Mathf.RoundToInt(baseDamage * damageMultiplier + flatDamage)
                : 0;

            if (isDefend)
            {
                playerDamage = 0;
            }

            targetStatus.hp = Mathf.Max(0, targetStatus.hp - playerDamage);
            if (targetStatus.label != null)
            {
                targetStatus.label.text = $"{targetStatus.enemy.DisplayName}  HP {targetStatus.hp}";
            }
            UpdateEnemyHpBar(targetStatus);

            ApplySkillEffectsToEnemy(skill, targetStatus);

            if (targetStatus.hp <= 0)
            {
                Debug.Log("[Battle] Enemy defeated.");
                activeEnemies.Remove(targetStatus.enemy);
                battleEnemyStatus.Remove(targetStatus.enemy);
                Destroy(targetStatus.enemy.gameObject);
                if (activeEnemies.Count == 0)
                {
                    CloseBattlePanel();
                    return;
                }

                RefreshBattlePanel();
                return;
            }

        }

        private void ApplyCompanionTurns(Player player)
        {
            if (player?.companions == null || player.companions.Count == 0)
            {
                return;
            }

            foreach (var companion in player.companions)
            {
                if (companion == null || activeEnemies.Count == 0)
                {
                    continue;
                }

                var target = battleTargetEnemy != null && battleEnemyStatus.ContainsKey(battleTargetEnemy)
                    ? battleTargetEnemy
                    : activeEnemies[0];

                if (!battleEnemyStatus.TryGetValue(target, out var status))
                {
                    continue;
                }

                var damage = Mathf.Max(1, 2 + companion.level);
                status.hp = Mathf.Max(0, status.hp - damage);
                if (status.label != null)
                {
                    status.label.text = $"{status.enemy.DisplayName}  HP {status.hp}";
                }

                if (status.hp <= 0)
                {
                    Debug.Log("[Battle] Enemy defeated by companion.");
                    activeEnemies.Remove(status.enemy);
                    battleEnemyStatus.Remove(status.enemy);
                    Destroy(status.enemy.gameObject);
                }
            }

            if (activeEnemies.Count > 0)
            {
                UpdateBattleTargetHighlight();
            }
        }

        private void ApplySkillEffectsToEnemy(SkillDefinition skill, BattleEnemyStatus status)
        {
            if (status == null || skill?.effects == null || skill.effects.Count == 0)
            {
                return;
            }

            foreach (var effect in skill.effects)
            {
                if (effect == null || string.IsNullOrWhiteSpace(effect.type))
                {
                    continue;
                }

                switch (effect.type)
                {
                    case "stun":
                        status.stunTurns = Mathf.Max(status.stunTurns, Mathf.Max(1, effect.duration));
                        break;
                    case "debuff_attack":
                        status.attackModifier = Mathf.Min(0, effect.value);
                        status.attackDebuffTurns = Mathf.Max(status.attackDebuffTurns, Mathf.Max(1, effect.duration));
                        break;
                    case "burn":
                        status.burnDamage = Mathf.Max(status.burnDamage, Mathf.Max(1, effect.value));
                        status.burnTurns = Mathf.Max(status.burnTurns, Mathf.Max(1, effect.duration));
                        break;
                }
            }
        }

        private void ResolveEnemyTurns()
        {
            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null)
            {
                return;
            }

            foreach (var status in new List<BattleEnemyStatus>(battleEnemyStatus.Values))
            {
                if (status == null)
                {
                    continue;
                }

                if (status.burnTurns > 0)
                {
                    status.hp = Mathf.Max(0, status.hp - Mathf.Max(0, status.burnDamage));
                    status.burnTurns = Mathf.Max(0, status.burnTurns - 1);
                    if (status.label != null)
                    {
                        status.label.text = $"{status.enemy.DisplayName}  HP {status.hp}";
                    }
                    UpdateEnemyHpBar(status);
                    UpdateEnemyHpBar(status);

                    if (status.hp <= 0)
                    {
                        Debug.Log("[Battle] Enemy defeated.");
                        activeEnemies.Remove(status.enemy);
                        battleEnemyStatus.Remove(status.enemy);
                        Destroy(status.enemy.gameObject);
                        continue;
                    }
                }
            }

            if (activeEnemies.Count == 0)
            {
                CloseBattlePanel();
                return;
            }

            foreach (var status in battleEnemyStatus.Values)
            {
                if (status == null || status.enemy == null)
                {
                    continue;
                }

                if (status.stunTurns > 0)
                {
                    status.stunTurns = Mathf.Max(0, status.stunTurns - 1);
                    continue;
                }

                var enemyAttackBase = status.enemy.Definition != null ? Mathf.Max(1, status.enemy.Definition.attackPoints) : 2;
                var enemyAttack = enemyAttackBase + status.attackModifier;
                if (status.attackDebuffTurns > 0)
                {
                    status.attackDebuffTurns = Mathf.Max(0, status.attackDebuffTurns - 1);
                    if (status.attackDebuffTurns == 0)
                    {
                        status.attackModifier = 0;
                    }
                }

                var enemyDamage = Mathf.Max(1, enemyAttack);
                battlePlayerHp = Mathf.Max(0, battlePlayerHp - enemyDamage);
                if (battlePlayerEntry != null)
                {
                    battlePlayerEntry.text = $"{player.name} (You)  HP {battlePlayerHp}";
                }
                UpdatePlayerBattleBars();
                UpdatePlayerBattleBars();

                player.hitPoints = Mathf.Max(0, battlePlayerHp);
                if (battlePlayerHp <= 0)
                {
                    Debug.Log("[Battle] Player defeated.");
                    CloseBattlePanel();
                    return;
                }
            }
        }

        private void UpdateEnemyHpBar(BattleEnemyStatus status)
        {
            if (status == null || status.hpFill == null)
            {
                return;
            }

            status.hpFill.fillAmount = status.maxHp > 0 ? Mathf.Clamp01((float)status.hp / status.maxHp) : 0f;
        }

        private void UpdatePlayerBattleBars()
        {
            if (!battleActorStatus.TryGetValue("player", out var status) || status == null)
            {
                partyHudActorStatus.TryGetValue("player", out status);
            }

            if (status == null)
            {
                return;
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null)
            {
                return;
            }

            if (status.hpFill != null)
            {
                var maxHp = player.maxHitPoints > 0 ? player.maxHitPoints : battlePlayerHp;
                status.hpFill.fillAmount = maxHp > 0 ? Mathf.Clamp01((float)battlePlayerHp / maxHp) : 0f;
            }

            if (status.resourceFill != null)
            {
                var maxMana = player.maxMana > 0 ? player.maxMana : player.mana;
                status.resourceFill.fillAmount = maxMana > 0 ? Mathf.Clamp01((float)player.mana / maxMana) : 0f;
            }
        }

        private void RefreshChestItems()
        {
            if (chestItemsRoot == null)
            {
                return;
            }

            for (var i = chestItemsRoot.childCount - 1; i >= 0; i--)
            {
                Destroy(chestItemsRoot.GetChild(i).gameObject);
            }

            if (activeChest == null)
            {
                Debug.Log("[ChestUI] RefreshChestItems with no active chest.");
                return;
            }

            var chestItems = activeChest.Items;
            Debug.Log($"[ChestUI] RefreshChestItems {activeChest.ChestId} count {chestItems?.Count ?? 0}");
            if (chestItems == null || chestItems.Count == 0)
            {
                CreateChestEmptyLabel();
                return;
            }

            var displayItems = BuildChestDisplayItems();
            if (displayItems.Count == 0)
            {
                CreateChestEmptyLabel();
                return;
            }

            for (var i = 0; i < displayItems.Count; i++)
            {
                var entry = displayItems[i];
                if (entry == null || entry.item == null)
                {
                    continue;
                }

                CreateChestItemSlot(chestItemsRoot, entry.item, i, entry.count);
            }

            LayoutRebuilder.ForceRebuildLayoutImmediate(chestItemsRoot);
            Canvas.ForceUpdateCanvases();
            Debug.Log($"[ChestUI] Spawned {chestItemsRoot.childCount} item rows.");
        }

        private void CreateChestEmptyLabel()
        {
            return;
        }

        private List<ChestDisplayItem> BuildChestDisplayItems()
        {
            var displayItems = new List<ChestDisplayItem>();
            if (activeChest == null)
            {
                return displayItems;
            }

            var stackables = new Dictionary<string, ChestDisplayItem>(StringComparer.OrdinalIgnoreCase);
            var chestItems = activeChest.Items;
            if (chestItems == null)
            {
                return displayItems;
            }

            for (var i = 0; i < chestItems.Count; i++)
            {
                var item = chestItems[i];
                if (item == null)
                {
                    continue;
                }

                var definition = GetItemDefinition(item);
                if (definition != null && definition.stackable)
                {
                    if (stackables.TryGetValue(item.id, out var existing))
                    {
                        existing.count += Mathf.Max(1, item.quantity);
                        continue;
                    }

                    var entry = new ChestDisplayItem
                    {
                        item = item,
                        count = Mathf.Max(1, item.quantity),
                        itemId = item.id
                    };
                    stackables[item.id] = entry;
                    displayItems.Add(entry);
                    continue;
                }

                displayItems.Add(new ChestDisplayItem
                {
                    item = item,
                    count = 1,
                    itemId = item.id
                });
            }

            return displayItems;
        }

        private void TakeSingleItem(Item item)
        {
            if (item == null || activeChest == null)
            {
                return;
            }

            var definition = GetItemDefinition(item);
            if (definition != null && definition.stackable)
            {
                var taken = activeChest.TakeAllById(item.id);
                if (taken != null)
                {
                    AddItemToInventory(taken);
                    var inventory = GameState.Instance?.CurrentSave?.player?.inventory;
                    Debug.Log($"[Inventory] Added item {taken.id} x{taken.quantity}. Count now {inventory?.Count ?? 0}.");
                }
            }
            else if (activeChest.TryTakeItem(item))
            {
                AddItemToInventory(item);
                var inventory = GameState.Instance?.CurrentSave?.player?.inventory;
                Debug.Log($"[Inventory] Added item {item.id}. Count now {inventory?.Count ?? 0}.");
            }

            RefreshChestItems();
            RefreshInventoryUI();
        }

        private void TakeAllFromChest()
        {
            if (activeChest == null)
            {
                return;
            }

            var transferItems = new List<Item>();
            activeChest.TakeAll(transferItems);
            for (var i = 0; i < transferItems.Count; i++)
            {
                AddItemToInventory(transferItems[i]);
            }

            var inventory = GameState.Instance?.CurrentSave?.player?.inventory;
            Debug.Log($"[Inventory] Took all. Count now {inventory?.Count ?? 0}.");
            RefreshChestItems();
            RefreshInventoryUI();
            CloseChestIfOpen();
        }

        private void RefreshInventoryUI()
        {
            if (inventoryFilterPanels == null || inventoryFilterPanels.Count == 0)
            {
                Debug.LogWarning("[Inventory] No inventory panels to refresh.");
                return;
            }

            Debug.Log("[Inventory] Refreshing inventory UI.");
            for (var i = 0; i < inventoryFilterPanels.Count; i++)
            {
                var panel = inventoryFilterPanels[i];
                if (panel == null)
                {
                    continue;
                }

                for (var childIndex = panel.transform.childCount - 1; childIndex >= 0; childIndex--)
                {
                    Destroy(panel.transform.GetChild(childIndex).gameObject);
                }

                var filterLabel = panel.name.Replace("Panel", string.Empty);
                CreateInventoryScrollGrid(panel.transform, 8, filterLabel);
            }

            currentInventoryFilter = "All";
            ShowInventoryFilter(currentInventoryFilter);
        }

        private void RefreshCompanionsTab()
        {
            if (companionsListRoot == null)
            {
                return;
            }

            for (var i = companionsListRoot.childCount - 1; i >= 0; i--)
            {
                Destroy(companionsListRoot.GetChild(i).gameObject);
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || player.companions == null || player.companions.Count == 0)
            {
                CreatePlaceholderText(companionsListRoot, "No companions in your party yet.");
                return;
            }

            foreach (var companion in player.companions)
            {
                if (companion == null)
                {
                    continue;
                }

                var cardObject = new GameObject($"{companion.id}_Card");
                cardObject.transform.SetParent(companionsListRoot, false);
                var rect = cardObject.AddComponent<RectTransform>();
                rect.sizeDelta = new Vector2(760f, 60f);

                var image = cardObject.AddComponent<Image>();
                image.sprite = MenuStyling.GetRoundedButtonSprite();
                image.type = Image.Type.Sliced;
                image.color = new Color(0.2f, 0.2f, 0.22f, 0.9f);

                var textObject = new GameObject("Label");
                textObject.transform.SetParent(cardObject.transform, false);
                var textRect = textObject.AddComponent<RectTransform>();
                textRect.anchorMin = Vector2.zero;
                textRect.anchorMax = Vector2.one;
                textRect.offsetMin = new Vector2(12f, 8f);
                textRect.offsetMax = new Vector2(-12f, -8f);

                var label = textObject.AddComponent<TextMeshProUGUI>();
                var name = !string.IsNullOrWhiteSpace(companion.name) ? companion.name : companion.id;
                label.text = $"{name}  (Level {Mathf.Max(1, companion.level)})";
                label.fontSize = 18f;
                label.alignment = TextAlignmentOptions.Left;
                label.color = new Color(0.92f, 0.88f, 0.8f, 1f);
            }
        }


        private void CreateChestItemSlot(Transform parent, Item item, int index, int quantity)
        {
            var slotObject = new GameObject($"ChestItemSlot_{index}");
            slotObject.transform.SetParent(parent, false);
            var slotRect = slotObject.AddComponent<RectTransform>();
            slotRect.sizeDelta = new Vector2(70f, 70f);

            var background = slotObject.AddComponent<Image>();
            background.sprite = GetSolidSprite();
            background.color = new Color(0.25f, 0.25f, 0.28f, 1f);

            var button = slotObject.AddComponent<Button>();
            button.onClick.RemoveAllListeners();
            button.onClick.AddListener(() => TakeSingleItem(item));

            var definition = GetItemDefinition(item);
            CreateInventoryItemIcon(slotObject.transform, item, definition, quantity);
        }

        private GameObject CreateItemActionPanel(Transform parent)
        {
            var panelObject = new GameObject("ItemActionPanel");
            panelObject.transform.SetParent(parent, false);
            var rect = panelObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = new Vector2(0f, 0f);
            rect.sizeDelta = new Vector2(320f, 220f);

            var image = panelObject.AddComponent<Image>();
            image.color = new Color(0.08f, 0.08f, 0.1f, 0.85f);
            image.sprite = MenuStyling.GetRoundedButtonSprite();
            image.type = Image.Type.Sliced;

            itemActionTitle = CreatePanelTitleText(panelObject.transform, "Item");
            if (itemActionTitle != null)
            {
                itemActionTitle.fontSize = 20f;
                itemActionTitle.color = Color.white;
            }

            itemUseButton = CreateItemActionButton(panelObject.transform, "Use Item");
            var useRect = itemUseButton.GetComponent<RectTransform>();
            useRect.anchorMin = new Vector2(0.5f, 0.5f);
            useRect.anchorMax = new Vector2(0.5f, 0.5f);
            useRect.pivot = new Vector2(0.5f, 0.5f);
            useRect.anchoredPosition = new Vector2(0f, 30f);
            itemUseButton.onClick.RemoveAllListeners();
            itemUseButton.onClick.AddListener(UseSelectedItem);

            itemEquipButton = CreateItemActionButton(panelObject.transform, "Equip Item");
            var equipRect = itemEquipButton.GetComponent<RectTransform>();
            equipRect.anchorMin = new Vector2(0.5f, 0.5f);
            equipRect.anchorMax = new Vector2(0.5f, 0.5f);
            equipRect.pivot = new Vector2(0.5f, 0.5f);
            equipRect.anchoredPosition = new Vector2(0f, -20f);
            itemEquipButton.onClick.RemoveAllListeners();
            itemEquipButton.onClick.AddListener(EquipSelectedItem);

            itemDropButton = CreateItemActionButton(panelObject.transform, "Drop Item");
            var dropRect = itemDropButton.GetComponent<RectTransform>();
            dropRect.anchorMin = new Vector2(0.5f, 0.5f);
            dropRect.anchorMax = new Vector2(0.5f, 0.5f);
            dropRect.pivot = new Vector2(0.5f, 0.5f);
            dropRect.anchoredPosition = new Vector2(0f, -70f);
            itemDropButton.onClick.RemoveAllListeners();
            itemDropButton.onClick.AddListener(DropSelectedItem);

            panelObject.SetActive(false);
            return panelObject;
        }

        private GameObject CreateActionBar(Transform parent)
        {
            var panelObject = new GameObject("ActionBar");
            panelObject.transform.SetParent(parent, false);
            var rect = panelObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 0f);
            rect.anchorMax = new Vector2(0.5f, 0f);
            rect.pivot = new Vector2(0.5f, 0f);
            rect.anchoredPosition = new Vector2(0f, 12f);
            rect.sizeDelta = new Vector2(ActionBarPanelWidth, ActionBarPanelHeightSingleRow);

            var background = panelObject.AddComponent<Image>();
            background.color = new Color(0.08f, 0.08f, 0.1f, 0.85f);
            background.sprite = MenuStyling.GetRoundedButtonSprite();
            background.type = Image.Type.Sliced;

            var contentObject = new GameObject("ActionBarContent");
            contentObject.transform.SetParent(panelObject.transform, false);
            actionBarContent = contentObject.AddComponent<RectTransform>();
            actionBarContent.anchorMin = new Vector2(0f, 0f);
            actionBarContent.anchorMax = new Vector2(1f, 1f);
            actionBarContent.offsetMin = new Vector2(12f, 8f);
            actionBarContent.offsetMax = new Vector2(-44f, -8f);

            actionBarGrid = contentObject.AddComponent<GridLayoutGroup>();
            actionBarGrid.cellSize = new Vector2(ActionBarSlotWidth, ActionBarSlotWidth);
            actionBarGrid.spacing = new Vector2(ActionBarSlotSpacing, ActionBarSlotSpacing);
            actionBarGrid.constraint = GridLayoutGroup.Constraint.FixedColumnCount;
            actionBarGrid.constraintCount = ActionBarSlotCount;
            actionBarGrid.childAlignment = TextAnchor.MiddleLeft;
            battleActionsRoot = contentObject.transform;

            var toggleObject = new GameObject("ActionBarToggle");
            toggleObject.transform.SetParent(panelObject.transform, false);
            var toggleRect = toggleObject.AddComponent<RectTransform>();
            toggleRect.anchorMin = new Vector2(1f, 0.5f);
            toggleRect.anchorMax = new Vector2(1f, 0.5f);
            toggleRect.pivot = new Vector2(1f, 0.5f);
            toggleRect.anchoredPosition = new Vector2(-12f, 0f);
            toggleRect.sizeDelta = new Vector2(24f, 24f);

            var toggleImage = toggleObject.AddComponent<Image>();
            toggleImage.sprite = GetSolidSprite();
            toggleImage.color = new Color(0.2f, 0.2f, 0.25f, 0.9f);

            var toggleLabel = new GameObject("Label");
            toggleLabel.transform.SetParent(toggleObject.transform, false);
            var toggleLabelRect = toggleLabel.AddComponent<RectTransform>();
            toggleLabelRect.anchorMin = Vector2.zero;
            toggleLabelRect.anchorMax = Vector2.one;
            toggleLabelRect.offsetMin = Vector2.zero;
            toggleLabelRect.offsetMax = Vector2.zero;

            var toggleText = toggleLabel.AddComponent<TextMeshProUGUI>();
            toggleText.text = "▾";
            toggleText.fontSize = 16f;
            toggleText.alignment = TextAlignmentOptions.Center;
            toggleText.color = Color.white;

            var toggleButton = toggleObject.AddComponent<Button>();
            toggleButton.onClick.AddListener(ToggleActionBarExpand);

            UpdateActionBarLayout();
            panelObject.SetActive(true);
            return panelObject;
        }

        private void ToggleActionBarExpand()
        {
            actionBarExpanded = !actionBarExpanded;
            UpdateActionBarLayout();
            RefreshActionBarForCurrentActor();
        }

        private void UpdateActionBarLayout()
        {
            if (actionBarPanel == null || actionBarContent == null || actionBarGrid == null)
            {
                return;
            }

            var rows = actionBarExpanded ? 4 : 1;
            var height = ActionBarContentPaddingV + rows * ActionBarSlotWidth + (rows - 1) * ActionBarSlotSpacing;
            var rect = actionBarPanel.GetComponent<RectTransform>();
            rect.sizeDelta = new Vector2(ActionBarPanelWidth, height);

            actionBarContent.offsetMin = new Vector2(12f, 8f);
            actionBarContent.offsetMax = new Vector2(-44f, -8f);
        }

        private Button CreateItemActionButton(Transform parent, string label)
        {
            var buttonObject = new GameObject($"{label.Replace(" ", string.Empty)}Button");
            buttonObject.transform.SetParent(parent, false);
            var rect = buttonObject.AddComponent<RectTransform>();
            rect.sizeDelta = new Vector2(220f, 40f);

            var image = buttonObject.AddComponent<Image>();
            image.sprite = GetSolidSprite();
            image.color = new Color(0f, 0f, 0f, 0.25f);

            var button = buttonObject.AddComponent<Button>();

            var labelObject = new GameObject("Label");
            labelObject.transform.SetParent(buttonObject.transform, false);
            var labelRect = labelObject.AddComponent<RectTransform>();
            labelRect.anchorMin = Vector2.zero;
            labelRect.anchorMax = Vector2.one;
            labelRect.offsetMin = Vector2.zero;
            labelRect.offsetMax = Vector2.zero;

            var text = labelObject.AddComponent<TextMeshProUGUI>();
            text.text = label;
            text.fontSize = 18f;
            text.alignment = TextAlignmentOptions.Center;
            text.color = Color.white;

            return button;
        }

        private void OpenItemActionMenu(Item item, ItemDefinition definition)
        {
            if (item == null || itemActionPanel == null)
            {
                return;
            }

            selectedItem = item;
            selectedItemDefinition = definition ?? GetItemDefinition(item);
            if (itemActionTitle != null)
            {
                var label = !string.IsNullOrWhiteSpace(selectedItemDefinition?.name) ? selectedItemDefinition.name : item.id;
                itemActionTitle.text = label ?? "Item";
            }

            var canUse = selectedItemDefinition != null && selectedItemDefinition.consumableData != null;
            var canEquip = selectedItemDefinition != null && (selectedItemDefinition.weaponData != null || selectedItemDefinition.armorData != null);
            if (itemUseButton != null) itemUseButton.interactable = canUse;
            if (itemEquipButton != null) itemEquipButton.interactable = canEquip;

            itemActionPanel.SetActive(true);
            itemActionPanel.transform.SetAsLastSibling();
        }

        private void CloseItemActionMenu()
        {
            if (itemActionPanel != null)
            {
                itemActionPanel.SetActive(false);
            }

            selectedItem = null;
            selectedItemDefinition = null;
        }

        private void UseSelectedItem()
        {
            if (selectedItem == null || selectedItemDefinition == null || selectedItemDefinition.consumableData == null)
            {
                return;
            }

            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null)
            {
                return;
            }

            ApplyConsumableEffect(selectedItemDefinition);
            RemoveItemById(selectedItem.id);
            RefreshInventoryUI();
            CloseItemActionMenu();
        }

        private void EquipSelectedItem()
        {
            if (selectedItem == null || selectedItemDefinition == null)
            {
                return;
            }

            var slotLabel = ResolveEquipSlot(selectedItemDefinition);
            if (string.IsNullOrWhiteSpace(slotLabel))
            {
                return;
            }

            if (EquipItemToSlot(selectedItem, selectedItemDefinition, slotLabel))
            {
                RefreshInventoryUI();
                CloseItemActionMenu();
            }
        }

        private void DropSelectedItem()
        {
            if (selectedItem == null)
            {
                return;
            }

            RemoveItemFromInventory(selectedItem);
            RefreshInventoryUI();
            CloseItemActionMenu();
        }

        private string ResolveEquipSlot(ItemDefinition definition)
        {
            if (definition == null)
            {
                return null;
            }

            if (definition.armorData != null && !string.IsNullOrWhiteSpace(definition.armorData.slot))
            {
                return definition.armorData.slot;
            }

            if (definition.weaponData != null)
            {
                if (string.Equals(definition.weaponData.weaponType, "bow", StringComparison.OrdinalIgnoreCase))
                {
                    return "Bow";
                }

                if (string.Equals(definition.weaponData.weaponType, "shield", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(definition.weaponData.weaponType, "offhand", StringComparison.OrdinalIgnoreCase))
                {
                    return "Off-Hand";
                }

                return "Main Hand";
            }

            return null;
        }

        private bool EquipItemToSlot(Item item, ItemDefinition definition, string slotLabel)
        {
            if (item == null || definition == null || string.IsNullOrWhiteSpace(slotLabel))
            {
                return false;
            }

            var normalized = NormalizeSlotLabel(slotLabel);
            if (!equipmentSlotRoots.TryGetValue(normalized, out var slotTransform) || slotTransform == null)
            {
                return false;
            }

            if (slotTransform.GetComponentInChildren<InventoryItemDragHandler>() != null)
            {
                return false;
            }

            if (!RemoveItemFromInventory(item))
            {
                return false;
            }

            CreateInventoryItemIcon(slotTransform, item, definition, Mathf.Max(1, item.quantity));
            var dragHandler = slotTransform.GetComponentInChildren<InventoryItemDragHandler>();
            if (dragHandler != null)
            {
                dragHandler.IsEquipped = true;
                dragHandler.EquippedSlotLabel = slotLabel;
                var rect = dragHandler.rectTransform;
                rect.anchorMin = Vector2.zero;
                rect.anchorMax = Vector2.one;
                rect.offsetMin = new Vector2(6f, 6f);
                rect.offsetMax = new Vector2(-6f, -6f);
                rect.sizeDelta = Vector2.zero;
            }

            ApplyEquipmentToCharacter(slotLabel, definition);
            return true;
        }

        private void ApplyConsumableEffect(ItemDefinition definition)
        {
            var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
            if (player == null || definition?.consumableData == null)
            {
                return;
            }

            var effectType = definition.consumableData.effectType;
            var effectValue = definition.consumableData.effectValue;
            if (string.Equals(effectType, "heal", StringComparison.OrdinalIgnoreCase))
            {
                var maxHp = player.maxHitPoints > 0 ? player.maxHitPoints : player.hitPoints;
                player.hitPoints = Mathf.Min(maxHp, player.hitPoints + effectValue);
                battlePlayerHp = player.hitPoints;
                if (battlePlayerEntry != null)
                {
                    battlePlayerEntry.text = $"{player.name} (You)  HP {battlePlayerHp}";
                }
                UpdatePlayerBattleBars();
            }
            else if (string.Equals(effectType, "restoreMana", StringComparison.OrdinalIgnoreCase))
            {
                var maxMana = player.maxMana > 0 ? player.maxMana : player.mana;
                player.mana = Mathf.Min(maxMana, player.mana + effectValue);
                UpdatePlayerBattleBars();
            }
        }

        private TextMeshProUGUI CreateChestTitle(Transform parent)
        {
            var titleObject = new GameObject("ChestTitle");
            titleObject.transform.SetParent(parent, false);
            var rect = titleObject.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.5f, 1f);
            rect.anchorMax = new Vector2(0.5f, 1f);
            rect.pivot = new Vector2(0.5f, 1f);
            rect.anchoredPosition = new Vector2(0f, -24f);
            rect.sizeDelta = new Vector2(600f, 40f);

            var text = titleObject.AddComponent<TextMeshProUGUI>();
            text.text = "Chest";
            text.fontSize = 32f;
            text.alignment = TextAlignmentOptions.Center;
            text.color = MenuStyling.Theme != null ? MenuStyling.Theme.inkColor : new Color(0.15f, 0.1f, 0.05f, 1f);
            return text;
        }

        private void SaveToSlot(int saveSlotIndex)
        {
            var gameState = GameState.Instance;
            if (gameState == null || gameState.CurrentSave == null)
            {
                Debug.LogWarning("[UI] No active save data to write.");
                return;
            }

            var playerObject = GameObject.Find("PlayerCharacter");
            if (playerObject != null && gameState.CurrentSave.player != null)
            {
                var position = playerObject.transform.position;
                gameState.CurrentSave.player.position = new Vector2(position.x, position.y);
                gameState.CurrentSave.hasPlayerPosition = true;
            }

            var characterIndex = GetCurrentCharacterIndex();
            var globalSlotIndex = GetGlobalSlotIndex(characterIndex, saveSlotIndex);
            SaveManager.SaveSlot(globalSlotIndex, gameState.CurrentSave);
            PlayerPrefs.SetInt("FableForge_SelectedCharacter", characterIndex);
            PlayerPrefs.SetInt("FableForge_SelectedSaveSlot", saveSlotIndex);
            PlayerPrefs.Save();
            Debug.Log($"[UI] Saved game to slot {globalSlotIndex}.");
        }

        private void LoadFromSlot(int saveSlotIndex)
        {
            var characterIndex = GetCurrentCharacterIndex();
            var globalSlotIndex = GetGlobalSlotIndex(characterIndex, saveSlotIndex);
            PlayerPrefs.SetInt("FableForge_SelectedCharacter", characterIndex);
            PlayerPrefs.SetInt("FableForge_SelectedSaveSlot", saveSlotIndex);
            PlayerPrefs.Save();
            CleanupGameplayObjects();
            GameFlow.ContinueGame(globalSlotIndex);
        }

        private void ReturnToMainMenu()
        {
            HideAllPanels();
            CleanupGameplayObjects();

            var startScreen = StartScreenController.GetOrCreate();
            startScreen.Activate();
            startScreen.ShowMainMenu();

            var characterCreation = UnityEngine.Object.FindFirstObjectByType<CharacterCreationBootstrap>();
            if (characterCreation != null)
            {
                characterCreation.Deactivate();
            }

            var uiRoot = GameObject.Find("GameUI");
            if (uiRoot != null)
            {
                Destroy(uiRoot);
            }
        }

        private int GetCurrentCharacterIndex()
        {
            var selected = PlayerPrefs.GetInt("FableForge_SelectedCharacter", -1);
            if (selected >= 0 && PlayerPrefs.HasKey($"{CharacterKeyPrefix}{selected}_Name"))
            {
                return selected;
            }

            var saveCharacter = GameState.Instance != null ? GameState.Instance.CurrentSave?.character : null;
            if (saveCharacter != null)
            {
                var indices = CharacterIndexRegistry.GetIndices();
                foreach (var index in indices)
                {
                    var name = PlayerPrefs.GetString($"{CharacterKeyPrefix}{index}_Name", string.Empty);
                    var storedClass = PlayerPrefs.GetString($"{CharacterKeyPrefix}{index}_Class", string.Empty);
                    if (string.Equals(name, saveCharacter.name, StringComparison.OrdinalIgnoreCase) &&
                        (string.IsNullOrWhiteSpace(storedClass) ||
                         string.Equals(storedClass, saveCharacter.characterClass.ToString(), StringComparison.OrdinalIgnoreCase)))
                    {
                        selected = index;
                        break;
                    }
                }
            }

            if (selected < 0)
            {
                selected = 0;
            }

            PlayerPrefs.SetInt("FableForge_SelectedCharacter", selected);
            PlayerPrefs.Save();
            return selected;
        }

        private int GetGlobalSlotIndex(int characterIndex, int saveSlotIndex)
        {
            return characterIndex * MaxSaveSlotsPerCharacter + saveSlotIndex;
        }

        private bool SaveSlotHasData(int characterIndex, int saveSlotIndex)
        {
            if (characterIndex < 0 || saveSlotIndex < 0)
            {
                return false;
            }

            var path = SaveManager.GetSlotPath(GetGlobalSlotIndex(characterIndex, saveSlotIndex));
            return File.Exists(path);
        }

        private string GetSaveSlotLabel(int characterIndex, int saveSlotIndex, bool includeOverwriteLabel)
        {
            var globalSlotIndex = GetGlobalSlotIndex(characterIndex, saveSlotIndex);
            var saveData = SaveManager.LoadSlot(globalSlotIndex);
            if (saveData == null)
            {
                return $"Slot {saveSlotIndex + 1} - New Save";
            }

            var timestamp = GetSaveTimestamp(saveData.savedAtUnix);
            if (includeOverwriteLabel)
            {
                return $"Slot {saveSlotIndex + 1} - Overwrite ({timestamp})";
            }

            return $"Slot {saveSlotIndex + 1} - {timestamp}";
        }

        private string GetSaveTimestamp(long savedAtUnix)
        {
            if (savedAtUnix <= 0)
            {
                return "Unknown Date";
            }

            var date = DateTimeOffset.FromUnixTimeSeconds(savedAtUnix).ToLocalTime().DateTime;
            return date.ToString("MMM d, yyyy h:mm tt");
        }

        private void CleanupGameplayObjects()
        {
            var playerObject = GameObject.Find("PlayerCharacter");
            if (playerObject != null)
            {
                Destroy(playerObject);
            }

            var tiledMap = GameObject.Find("TiledMap");
            if (tiledMap != null)
            {
                Destroy(tiledMap);
            }

            var worldPreview = GameObject.Find("WorldPreview");
            if (worldPreview != null)
            {
                Destroy(worldPreview);
            }

            var worldEntities = GameObject.Find("WorldEntities");
            if (worldEntities != null)
            {
                Destroy(worldEntities);
            }

            if (GameSceneController.Instance != null)
            {
                Destroy(GameSceneController.Instance.gameObject);
            }
        }

        [Serializable]
        private class BuildableStructureList
        {
            public List<BuildableStructureDefinition> structures;
        }

        [Serializable]
        private class BuildableStructureDefinition
        {
            public string id;
            public string name;
            public string description;
            public string structureType;
            public string tab;
            public string image;
        }

        [Serializable]
        private class SkillList
        {
            public List<SkillDefinition> skills;
        }

        [Serializable]
        private class SkillDefinition
        {
            public string id;
            public string name;
            public string description;
            public string type;
            public float? damageMultiplier;
            public int? baseDamage;
            public int? energyCost;
            public int? manaCost;
            public int? cooldown;
            public int? range;
            public string targetType;
            public List<SkillEffect> effects;
        }

        [Serializable]
        private class SkillEffect
        {
            public string type;
            public int duration;
            public int value;
        }

        private enum BattleActionKind
        {
            Skill,
            Item
        }

        private class BattleAction
        {
            public BattleActionKind kind;
            public string id;
            public string label;
        }

        private class BattleEnemyStatus
        {
            public EnemyInstance enemy;
            public int hp;
            public int maxHp;
            public int stunTurns;
            public int attackModifier;
            public int attackDebuffTurns;
            public int burnDamage;
            public int burnTurns;
            public TextMeshProUGUI label;
            public Button button;
            public Image background;
            public Image hpFill;
        }

        private enum BattleActorKind
        {
            Player,
            Companion
        }

        private class BattleActor
        {
            public string key;
            public BattleActorKind kind;
            public string name;
            public int level;
            public List<string> skillIds;
        }

        private class BattleActorStatus
        {
            public BattleActor actor;
            public Button button;
            public Image background;
            public TextMeshProUGUI label;
            public Image hpFill;
            public Image resourceFill;
        }

        private class ActionBarSlotDropTarget : MonoBehaviour, IDropHandler
        {
            public RuntimeGameUIBootstrap ui;
            public string actorKey;
            public int slotIndex;

            public void OnDrop(PointerEventData eventData)
            {
                if (eventData == null || eventData.pointerDrag == null || ui == null)
                {
                    return;
                }

                var dragHandler = eventData.pointerDrag.GetComponent<ActionBarActionDragHandler>();
                if (dragHandler == null)
                {
                    return;
                }

                if (!string.Equals(dragHandler.actorKey, actorKey, StringComparison.OrdinalIgnoreCase))
                {
                    return;
                }

                ui.MoveActionBarAction(actorKey, dragHandler.slotIndex, slotIndex);
                dragHandler.DropHandled = true;
            }
        }

        private class ActionBarActionDragHandler : MonoBehaviour, IBeginDragHandler, IDragHandler, IEndDragHandler
        {
            public RuntimeGameUIBootstrap ui;
            public string actorKey;
            public int slotIndex;
            public BattleAction action;
            public RectTransform rectTransform;
            public CanvasGroup canvasGroup;
            public bool DropHandled { get; set; }

            private Transform originalParent;
            private Vector2 originalPosition;

            public void OnBeginDrag(PointerEventData eventData)
            {
                if (rectTransform == null || ui == null || ui.rootCanvas == null)
                {
                    return;
                }

                DropHandled = false;
                originalParent = rectTransform.parent;
                originalPosition = rectTransform.anchoredPosition;
                rectTransform.SetParent(ui.rootCanvas.transform, true);
                if (canvasGroup != null)
                {
                    canvasGroup.blocksRaycasts = false;
                }
            }

            public void OnDrag(PointerEventData eventData)
            {
                if (rectTransform == null || ui == null || ui.rootCanvas == null || eventData == null)
                {
                    return;
                }

                rectTransform.anchoredPosition += eventData.delta / ui.rootCanvas.scaleFactor;
            }

            public void OnEndDrag(PointerEventData eventData)
            {
                if (rectTransform == null)
                {
                    return;
                }

                if (!DropHandled && originalParent != null)
                {
                    rectTransform.SetParent(originalParent, false);
                    rectTransform.anchoredPosition = originalPosition;
                }

                if (canvasGroup != null)
                {
                    canvasGroup.blocksRaycasts = true;
                }
            }
        }

        [Serializable]
        private class CompanionSkillList
        {
            public List<CompanionSkillDefinition> animals;
        }

        [Serializable]
        private class CompanionSkillDefinition
        {
            public string id;
            public string name;
            public List<string> skillIds;
            public int hitPoints;
        }

        private class InventoryDisplayItem
        {
            public Item item;
            public ItemDefinition definition;
            public int count;
            public string itemId;
        }

        private class ChestDisplayItem
        {
            public Item item;
            public int count;
            public string itemId;
        }

        [Serializable]
        private class ItemList
        {
            public List<ItemDefinition> items;
        }

        [Serializable]
        private class ItemDefinition
        {
            public string id;
            public string name;
            public string description;
            public string type;
            public bool stackable;
            public WeaponData weaponData;
            public ArmorData armorData;
            public ConsumableData consumableData;
        }

        [Serializable]
        private class ConsumableData
        {
            public string effectType;
            public int effectValue;
            public int? duration;
        }

        [Serializable]
        private class WeaponData
        {
            public string weaponType;
        }

        [Serializable]
        private class ArmorData
        {
            public string slot;
        }

        private class EquipmentSlotDropTarget : MonoBehaviour, IDropHandler
        {
            public RuntimeGameUIBootstrap ui;
            public string slotLabel;

            public void OnDrop(PointerEventData eventData)
            {
                if (eventData == null || eventData.pointerDrag == null)
                {
                    return;
                }

                var dragHandler = eventData.pointerDrag.GetComponent<InventoryItemDragHandler>();
                if (dragHandler == null || ui == null)
                {
                    return;
                }

                dragHandler.CurrentDropTarget = this;
                dragHandler.DropHandled = ui.TryEquipItemToSlot(dragHandler, slotLabel);
            }
        }

        private class InventorySlotDropTarget : MonoBehaviour, IDropHandler
        {
            public RuntimeGameUIBootstrap ui;
            public string targetItemId;
            public Item targetItem;

            public void OnDrop(PointerEventData eventData)
            {
                if (eventData == null || eventData.pointerDrag == null || ui == null)
                {
                    return;
                }

                var dragHandler = eventData.pointerDrag.GetComponent<InventoryItemDragHandler>();
                if (dragHandler == null)
                {
                    return;
                }

                ui.HandleInventoryDrop(dragHandler, targetItemId, targetItem);
                dragHandler.DropHandled = true;
            }
        }

        private class InventoryItemDragHandler : MonoBehaviour, IBeginDragHandler, IDragHandler, IEndDragHandler
        {
            public RuntimeGameUIBootstrap ui;
            public ItemDefinition definition;
            public Item item;
            public CanvasGroup canvasGroup;
            public RectTransform rectTransform;
            public EquipmentSlotDropTarget CurrentDropTarget { get; set; }
            public bool DropHandled { get; set; }
            public bool IsEquipped { get; set; }
            public string EquippedSlotLabel { get; set; }

            private Transform originalParent;
            private Vector2 originalPosition;
            private Vector2 originalAnchorMin;
            private Vector2 originalAnchorMax;
            private Vector2 originalOffsetMin;
            private Vector2 originalOffsetMax;
            private Vector2 originalSizeDelta;
            private Vector3 originalScale;

            public void OnBeginDrag(PointerEventData eventData)
            {
                if (rectTransform == null || ui == null || ui.rootCanvas == null)
                {
                    return;
                }

                DropHandled = false;
                CurrentDropTarget = null;
                originalParent = rectTransform.parent;
                originalPosition = rectTransform.anchoredPosition;
                originalAnchorMin = rectTransform.anchorMin;
                originalAnchorMax = rectTransform.anchorMax;
                originalOffsetMin = rectTransform.offsetMin;
                originalOffsetMax = rectTransform.offsetMax;
                originalSizeDelta = rectTransform.sizeDelta;
                originalScale = rectTransform.localScale;
                rectTransform.SetParent(ui.rootCanvas.transform, true);
                if (canvasGroup != null)
                {
                    canvasGroup.blocksRaycasts = false;
                }
            }

            public void OnDrag(PointerEventData eventData)
            {
                if (rectTransform == null || ui == null || ui.rootCanvas == null || eventData == null)
                {
                    return;
                }

                rectTransform.anchoredPosition += eventData.delta / ui.rootCanvas.scaleFactor;
            }

            public void OnEndDrag(PointerEventData eventData)
            {
                if (rectTransform == null)
                {
                    return;
                }

                if (!DropHandled && originalParent != null)
                {
                    rectTransform.SetParent(originalParent, false);
                    rectTransform.anchoredPosition = originalPosition;
                    rectTransform.anchorMin = originalAnchorMin;
                    rectTransform.anchorMax = originalAnchorMax;
                    rectTransform.offsetMin = originalOffsetMin;
                    rectTransform.offsetMax = originalOffsetMax;
                    rectTransform.sizeDelta = originalSizeDelta;
                    rectTransform.localScale = originalScale;
                }

                if (canvasGroup != null)
                {
                    canvasGroup.blocksRaycasts = true;
                }
            }
        }
    }
}
