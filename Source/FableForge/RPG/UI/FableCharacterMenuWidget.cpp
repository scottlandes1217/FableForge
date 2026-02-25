#include "RPG/UI/FableCharacterMenuWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/ButtonSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/ScrollBox.h"
#include "Components/SizeBox.h"
#include "Components/SlateWrapperTypes.h"
#include "Components/Spacer.h"
#include "Components/TextBlock.h"
#include "Components/UniformGridPanel.h"
#include "Components/UniformGridSlot.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Engine/DataTable.h"
#include "Engine/Texture2D.h"
#include "FableForgePlayerController.h"
#include "FableForge.h"
#include "RPG/Data/FableItemDefinitionTableRow.h"
#include "RPG/Data/FableSkillSystemTableRows.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "RPG/UI/FableActionButton.h"
#include "RPG/UI/FableInventorySlotWidget.h"
#include "TimerManager.h"

namespace
{
	const FName InventoryAction = TEXT("tab_inventory");
	const FName SkillsAction = TEXT("tab_skills");
	const FName CompanionsAction = TEXT("tab_companions");
	const FName BuildAction = TEXT("tab_build");
	const FName CloseMenuAction = TEXT("close_menu");

	const FName CategoryWeaponsAction = TEXT("cat_weapons");
	const FName CategoryArmorAction = TEXT("cat_armor");
	const FName CategoryConsumablesAction = TEXT("cat_consumables");
	const FName CategoryMiscAction = TEXT("cat_misc");
	const FName CategoryKeyItemsAction = TEXT("cat_key_items");
	const FName CategoryAllAction = TEXT("cat_all");
	const FName SkillCategoryAllAction = TEXT("skillcat_all");
	const TCHAR* SkillSelectActionPrefix = TEXT("skillselect_");
	const TCHAR* SkillCategoryActionPrefix = TEXT("skillcat_");

	const FLinearColor UiPanelColor(0.01f, 0.01f, 0.01f, 0.96f);
	const FLinearColor UiSectionColor(0.03f, 0.03f, 0.03f, 0.94f);
	const FLinearColor UiButtonColor(0.05f, 0.05f, 0.05f, 1.0f);
	const FLinearColor UiButtonSelectedColor(0.0f, 0.0f, 0.0f, 1.0f);
	const FLinearColor UiTextColor(0.95f, 0.95f, 0.95f, 1.0f);
	const FLinearColor UiMutedTextColor(0.72f, 0.72f, 0.72f, 1.0f);
	const TArray<FString> EquipmentSlotNames = {
		TEXT("Main Hand"),
		TEXT("Off Hand"),
		TEXT("Head"),
		TEXT("Chest"),
		TEXT("Hands"),
		TEXT("Legs"),
		TEXT("Feet"),
		TEXT("Back"),
		TEXT("Neck"),
		TEXT("Ring 1"),
		TEXT("Ring 2"),
		TEXT("Bow")
	};

	struct FEquipmentLayoutCell
	{
		int32 LogicalIndex;
		int32 Row;
		int32 Col;
	};

	const TArray<FEquipmentLayoutCell> EquipmentLayout = {
		{8, 0, 0},   // Neck
		{2, 0, 1},   // Head
		{7, 0, 2},   // Back
		{9, 1, 0},   // Ring 1
		{3, 1, 1},   // Chest
		{4, 1, 2},   // Hands
		{10, 2, 0},  // Ring 2
		{5, 2, 1},   // Legs
		{6, 2, 2},   // Feet
		{0, 3, 0},   // Main Hand
		{1, 3, 1},   // Off Hand
		{11, 3, 2}   // Bow
	};

	const TCHAR* ItemsDataTablePath = TEXT("/Game/Data/DT_Items.DT_Items");
	const TCHAR* WeaponsDataTablePath = TEXT("/Game/Data/DT_Weapons.DT_Weapons");
	const TCHAR* ArmorDataTablePath = TEXT("/Game/Data/DT_Armor.DT_Armor");
	const TCHAR* SkillsDataTablePath = TEXT("/Game/Data/DT_Skills.DT_Skills");

	FName CategoryFromType(const FString& InType)
	{
		const FString Type = InType.ToLower();
		if (Type == TEXT("weapon"))
		{
			return CategoryWeaponsAction;
		}

		if (Type == TEXT("armor"))
		{
			return CategoryArmorAction;
		}

		if (Type == TEXT("consumable"))
		{
			return CategoryConsumablesAction;
		}

		if (Type == TEXT("key") || Type == TEXT("keyitem") || Type == TEXT("key_item") || Type == TEXT("quest"))
		{
			return CategoryKeyItemsAction;
		}

		return CategoryMiscAction;
	}

	FString BuildIconToken(const FString& InName)
	{
		FString Compact = InName;
		Compact.ReplaceInline(TEXT("_"), TEXT(" "));
		TArray<FString> Words;
		Compact.ParseIntoArray(Words, TEXT(" "), true);

		FString Token;
		for (const FString& Word : Words)
		{
			if (Word.IsEmpty())
			{
				continue;
			}

			Token += Word.Left(1).ToUpper();
			if (Token.Len() >= 2)
			{
				return Token.Left(2);
			}
		}

		if (Token.Len() == 1)
		{
			return Token + TEXT("?");
		}

		return TEXT("??");
	}

	int32 ArmorSlotIndexFromString(const FString& InSlotName)
	{
		const FString Slot = InSlotName.ToLower();
		if (Slot == TEXT("offhand") || Slot == TEXT("off_hand") || Slot == TEXT("shield"))
		{
			return 1;
		}

		if (Slot == TEXT("head"))
		{
			return 2;
		}

		if (Slot == TEXT("chest"))
		{
			return 3;
		}

		if (Slot == TEXT("hands") || Slot == TEXT("arms"))
		{
			return 4;
		}

		if (Slot == TEXT("legs"))
		{
			return 5;
		}

		if (Slot == TEXT("feet"))
		{
			return 6;
		}

		if (Slot == TEXT("back"))
		{
			return 7;
		}

		if (Slot == TEXT("neck") || Slot == TEXT("amulet"))
		{
			return 8;
		}

		if (Slot == TEXT("ring"))
		{
			return 9;
		}

		if (Slot == TEXT("bow"))
		{
			return 11;
		}

		return INDEX_NONE;
	}

	FString CategoryDisplayName(FName Category)
	{
		if (Category == CategoryAllAction)
		{
			return TEXT("All");
		}

		if (Category == CategoryWeaponsAction)
		{
			return TEXT("Weapons");
		}

		if (Category == CategoryArmorAction)
		{
			return TEXT("Armor");
		}

		if (Category == CategoryConsumablesAction)
		{
			return TEXT("Consumables");
		}

		if (Category == CategoryKeyItemsAction)
		{
			return TEXT("Key Items");
		}

		return TEXT("Misc");
	}

	bool IsRingEquipmentSlotIndex(const int32 SlotIndex)
	{
		return SlotIndex == 9 || SlotIndex == 10;
	}

	TArray<FString> ParseDelimitedList(const FString& Source)
	{
		TArray<FString> Result;
		if (Source.IsEmpty())
		{
			return Result;
		}

		FString Normalized = Source;
		Normalized.ReplaceInline(TEXT(";"), TEXT("|"));
		if (!Normalized.Contains(TEXT("|")) && Normalized.Contains(TEXT(",")))
		{
			Normalized.ParseIntoArray(Result, TEXT(","), true);
		}
		else
		{
			Normalized.ParseIntoArray(Result, TEXT("|"), true);
		}

		for (FString& Entry : Result)
		{
			Entry = Entry.TrimStartAndEnd();
		}
		Result.RemoveAll([](const FString& Value) { return Value.IsEmpty(); });
		return Result;
	}

	FString HumanizeToken(const FString& Source)
	{
		if (Source.IsEmpty())
		{
			return FString();
		}

		FString Out = Source;
		Out.ReplaceInline(TEXT("_"), TEXT(" "));
		Out.ReplaceInline(TEXT("."), TEXT(" "));
		Out.ReplaceInline(TEXT(":"), TEXT(" "));
		if (!Out.IsEmpty())
		{
			Out[0] = FChar::ToUpper(Out[0]);
		}
		return Out;
	}

	FString JoinHumanizedList(const FString& Source)
	{
		const TArray<FString> Parts = ParseDelimitedList(Source);
		TArray<FString> Humanized;
		Humanized.Reserve(Parts.Num());
		for (const FString& Part : Parts)
		{
			Humanized.Add(HumanizeToken(Part));
		}
		return FString::Join(Humanized, TEXT(", "));
	}

	FString EnumToString(EFableSkillType Value)
	{
		switch (Value)
		{
		case EFableSkillType::Active: return TEXT("Active");
		case EFableSkillType::Passive: return TEXT("Passive");
		case EFableSkillType::Triggered: return TEXT("Triggered");
		default: return TEXT("Unknown");
		}
	}

	FString EnumToString(EFableSkillResourceType Value)
	{
		switch (Value)
		{
		case EFableSkillResourceType::Mana: return TEXT("Mana");
		case EFableSkillResourceType::Stamina: return TEXT("Stamina");
		case EFableSkillResourceType::Energy: return TEXT("Energy");
		case EFableSkillResourceType::Rage: return TEXT("Rage");
		case EFableSkillResourceType::None:
		default:
			return TEXT("None");
		}
	}

	FString EnumToString(EFableSkillTargetingMode Value)
	{
		switch (Value)
		{
		case EFableSkillTargetingMode::Self: return TEXT("Self");
		case EFableSkillTargetingMode::TargetUnit: return TEXT("Target Unit");
		case EFableSkillTargetingMode::Ground: return TEXT("Ground");
		case EFableSkillTargetingMode::Object: return TEXT("Object");
		case EFableSkillTargetingMode::Weapon: return TEXT("Weapon");
		case EFableSkillTargetingMode::Equipment: return TEXT("Equipment");
		case EFableSkillTargetingMode::Area: return TEXT("Area");
		default: return TEXT("Unknown");
		}
	}

	FString EnumToString(EFableSkillCategory Value)
	{
		switch (Value)
		{
		case EFableSkillCategory::Basic: return TEXT("Basic");
		case EFableSkillCategory::Light: return TEXT("Light");
		case EFableSkillCategory::Elemental: return TEXT("Elemental");
		case EFableSkillCategory::Arcane: return TEXT("Arcane");
		case EFableSkillCategory::Sword: return TEXT("Sword");
		case EFableSkillCategory::Shield: return TEXT("Shield");
		case EFableSkillCategory::Support: return TEXT("Support");
		case EFableSkillCategory::Movement: return TEXT("Movement");
		case EFableSkillCategory::Utility: return TEXT("Utility");
		default: return TEXT("Unknown");
		}
	}

	FName SkillCategoryActionFromEnum(EFableSkillCategory Category)
	{
		return *FString::Printf(TEXT("%s%s"), SkillCategoryActionPrefix, *EnumToString(Category).ToLower());
	}

	bool TryParseSkillCategoryAction(FName ActionId, FName& OutCategoryAction)
	{
		const FString ActionString = ActionId.ToString();
		if (!ActionString.StartsWith(SkillCategoryActionPrefix))
		{
			return false;
		}

		OutCategoryAction = ActionId;
		return true;
	}
}

TSharedRef<SWidget> UFableCharacterMenuWidget::RebuildWidget()
{
	Rebuild();
	return Super::RebuildWidget();
}

void UFableCharacterMenuWidget::NativeConstruct()
{
	Super::NativeConstruct();
	SetIsFocusable(true);
	Close();
}

void UFableCharacterMenuWidget::Open()
{
	SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	bInventoryLoaded = false;

	if (WidgetTree == nullptr || WidgetTree->RootWidget == nullptr || ContentRoot == nullptr)
	{
		Rebuild();
		return;
	}

	LoadInventoryFromSave();
	LoadItemDefinitionsFromUnityJson();
	RebuildTabContent();
}

void UFableCharacterMenuWidget::Close()
{
	SetVisibility(ESlateVisibility::Collapsed);
}

void UFableCharacterMenuWidget::Toggle()
{
	if (IsOpen())
	{
		Close();
	}
	else
	{
		Open();
	}
}

bool UFableCharacterMenuWidget::IsOpen() const
{
	const ESlateVisibility CurrentVisibility = GetVisibility();
	return CurrentVisibility != ESlateVisibility::Collapsed && CurrentVisibility != ESlateVisibility::Hidden;
}

void UFableCharacterMenuWidget::Rebuild()
{
	if (WidgetTree == nullptr)
	{
		return;
	}

	SlotWidgets.Reset();
	MainTabButtons.Reset();
	SkillRowActions.Reset();

	UCanvasPanel* Root = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("CharacterMenuRoot"));
	Root->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	WidgetTree->RootWidget = Root;

	UBorder* Frame = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("Frame"));
	Frame->SetBrushColor(UiPanelColor);
	Frame->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	if (UCanvasPanelSlot* FrameSlot = Root->AddChildToCanvas(Frame))
	{
		FrameSlot->SetAnchors(FAnchors(0.5f, 0.5f));
		FrameSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		FrameSlot->SetPosition(FVector2D(0.0f, -60.0f));
		FrameSlot->SetSize(FVector2D(1040.0f, 570.0f));
	}

	UVerticalBox* VBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("FrameVBox"));
	VBox->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	Frame->SetContent(VBox);

	UHorizontalBox* TabRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("TabRow"));
	if (UVerticalBoxSlot* TabRowSlot = VBox->AddChildToVerticalBox(TabRow))
	{
		TabRowSlot->SetPadding(FMargin(20.0f, 14.0f, 20.0f, 12.0f));
	}

	auto AddTabButton = [&](const FString& Label, FName ActionId, bool bSelected)
	{
		UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		Button->InitializeAction(ActionId);
		Button->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		Button->SetBackgroundColor(bSelected ? UiButtonSelectedColor : UiButtonColor);

		UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Text->SetText(FText::FromString(Label));
		Text->SetColorAndOpacity(FSlateColor(UiTextColor));
		Text->SetJustification(ETextJustify::Center);
		Button->AddChild(Text);
		if (UButtonSlot* TextSlot = Cast<UButtonSlot>(Text->Slot))
		{
			TextSlot->SetHorizontalAlignment(HAlign_Center);
			TextSlot->SetVerticalAlignment(VAlign_Center);
			TextSlot->SetPadding(FMargin(12.0f, 10.0f));
		}

		if (UHorizontalBoxSlot* HorizontalSlot = TabRow->AddChildToHorizontalBox(Button))
		{
			HorizontalSlot->SetPadding(FMargin(0.0f, 0.0f, 8.0f, 0.0f));
		}

		MainTabButtons.Add(ActionId, Button);
	};

	AddTabButton(TEXT("Inventory"), InventoryAction, ActiveTab == TEXT("inventory"));
	AddTabButton(TEXT("Skills"), SkillsAction, ActiveTab == TEXT("skills"));
	AddTabButton(TEXT("Companions"), CompanionsAction, ActiveTab == TEXT("companions"));
	AddTabButton(TEXT("Build"), BuildAction, ActiveTab == TEXT("build"));

	USpacer* TabRightSpacer = WidgetTree->ConstructWidget<USpacer>(USpacer::StaticClass(), TEXT("TabRightSpacer"));
	if (UHorizontalBoxSlot* TabSpacerSlot = TabRow->AddChildToHorizontalBox(TabRightSpacer))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		TabSpacerSlot->SetSize(FillSize);
	}

	UFableActionButton* CloseButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass(), TEXT("CloseButton"));
	CloseButton->InitializeAction(CloseMenuAction);
	CloseButton->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
	CloseButton->SetBackgroundColor(UiButtonColor);
	UTextBlock* CloseText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	CloseText->SetText(FText::FromString(TEXT("X")));
	CloseText->SetColorAndOpacity(FSlateColor(UiTextColor));
	CloseText->SetJustification(ETextJustify::Center);
	CloseButton->AddChild(CloseText);
	if (UButtonSlot* CloseTextSlot = Cast<UButtonSlot>(CloseText->Slot))
	{
		CloseTextSlot->SetHorizontalAlignment(HAlign_Center);
		CloseTextSlot->SetVerticalAlignment(VAlign_Center);
		CloseTextSlot->SetPadding(FMargin(10.0f, 4.0f));
	}
	if (UHorizontalBoxSlot* CloseSlot = TabRow->AddChildToHorizontalBox(CloseButton))
	{
		CloseSlot->SetHorizontalAlignment(HAlign_Right);
		CloseSlot->SetVerticalAlignment(VAlign_Center);
	}

	ContentRoot = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("TabContent"));
	ContentRoot->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	if (UVerticalBoxSlot* ContentSlot = VBox->AddChildToVerticalBox(ContentRoot))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		ContentSlot->SetSize(FillSize);
		ContentSlot->SetPadding(FMargin(20.0f, 0.0f, 20.0f, 14.0f));
	}
	RebuildTabContent();
}

void UFableCharacterMenuWidget::RefreshMainTabButtonStyles()
{
	auto UpdateButton = [&](FName ActionId, bool bSelected)
	{
		if (TObjectPtr<UFableActionButton>* ButtonPtr = MainTabButtons.Find(ActionId))
		{
			if (UFableActionButton* Button = ButtonPtr->Get())
			{
				Button->SetBackgroundColor(bSelected ? UiButtonSelectedColor : UiButtonColor);
			}
		}
	};

	UpdateButton(InventoryAction, ActiveTab == TEXT("inventory"));
	UpdateButton(SkillsAction, ActiveTab == TEXT("skills"));
	UpdateButton(CompanionsAction, ActiveTab == TEXT("companions"));
	UpdateButton(BuildAction, ActiveTab == TEXT("build"));
}

void UFableCharacterMenuWidget::QueueTabContentRebuild()
{
	if (bTabContentRebuildQueued)
	{
		return;
	}

	bTabContentRebuildQueued = true;
	if (UWorld* World = GetWorld())
	{
		World->GetTimerManager().SetTimerForNextTick(FTimerDelegate::CreateUObject(this, &UFableCharacterMenuWidget::PerformQueuedTabContentRebuild));
	}
	else
	{
		PerformQueuedTabContentRebuild();
	}
}

void UFableCharacterMenuWidget::PerformQueuedTabContentRebuild()
{
	bTabContentRebuildQueued = false;
	RefreshMainTabButtonStyles();
	RebuildTabContent();
}

void UFableCharacterMenuWidget::RebuildTabContent()
{
	if (ContentRoot == nullptr)
	{
		return;
	}

	ContentRoot->ClearChildren();
	SlotWidgets.Reset();

	if (ActiveTab == TEXT("inventory"))
	{
		BuildInventoryTab();
		return;
	}

	if (ActiveTab == TEXT("skills"))
	{
		BuildSkillsTab();
		return;
	}

	if (ActiveTab == TEXT("companions"))
	{
		BuildSimpleInfoTab(TEXT("Companions"), TEXT("No companions recruited yet."));
		return;
	}

	BuildSimpleInfoTab(TEXT("Build"), TEXT("No structures queued."));
}

void UFableCharacterMenuWidget::BuildInventoryTab()
{
	LoadInventoryFromSave();
	LoadItemDefinitionsFromUnityJson();

	UHorizontalBox* CategoryRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("InventoryCategoryRow"));
	if (UVerticalBoxSlot* CategoryRowSlot = ContentRoot->AddChildToVerticalBox(CategoryRow))
	{
		CategoryRowSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 12.0f));
	}

	auto AddCategoryButton = [&](const FString& Label, FName CategoryAction)
	{
		UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		Button->InitializeAction(CategoryAction);
		Button->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		Button->SetBackgroundColor(ActiveInventoryCategory == CategoryAction ? UiButtonSelectedColor : UiButtonColor);

		UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Text->SetText(FText::FromString(Label));
		Text->SetColorAndOpacity(FSlateColor(UiTextColor));
		Text->SetJustification(ETextJustify::Center);
		FSlateFontInfo FontInfo = Text->GetFont();
		FontInfo.Size = 15;
		Text->SetFont(FontInfo);
		Button->AddChild(Text);
		if (UButtonSlot* TextSlot = Cast<UButtonSlot>(Text->Slot))
		{
			TextSlot->SetHorizontalAlignment(HAlign_Center);
			TextSlot->SetVerticalAlignment(VAlign_Center);
			TextSlot->SetPadding(FMargin(10.0f, 8.0f));
		}

		if (UHorizontalBoxSlot* HorizontalSlot = CategoryRow->AddChildToHorizontalBox(Button))
		{
			FSlateChildSize FillSize;
			FillSize.SizeRule = ESlateSizeRule::Fill;
			FillSize.Value = 1.0f;
			HorizontalSlot->SetSize(FillSize);
			HorizontalSlot->SetPadding(FMargin(0.0f, 0.0f, 8.0f, 0.0f));
		}
	};

	AddCategoryButton(TEXT("All"), CategoryAllAction);
	AddCategoryButton(TEXT("Armor"), CategoryArmorAction);
	AddCategoryButton(TEXT("Weapons"), CategoryWeaponsAction);
	AddCategoryButton(TEXT("Consumables"), CategoryConsumablesAction);
	AddCategoryButton(TEXT("Misc"), CategoryMiscAction);
	AddCategoryButton(TEXT("Key Items"), CategoryKeyItemsAction);

	UHorizontalBox* MainRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("InventoryMainRow"));
	if (UVerticalBoxSlot* MainRowSlot = ContentRoot->AddChildToVerticalBox(MainRow))
	{
		MainRowSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 0.0f));
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		MainRowSlot->SetSize(FillSize);
		MainRowSlot->SetHorizontalAlignment(HAlign_Left);
	}

	UVerticalBox* LeftColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("InventoryLeftColumn"));
	if (UHorizontalBoxSlot* LeftSlot = MainRow->AddChildToHorizontalBox(LeftColumn))
	{
		LeftSlot->SetHorizontalAlignment(HAlign_Left);
		LeftSlot->SetPadding(FMargin(0.0f, 0.0f, 12.0f, 0.0f));
	}

	USizeBox* InventorySectionSize = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("InventorySectionSize"));
	InventorySectionSize->SetWidthOverride(682.0f);
	InventorySectionSize->SetHeightOverride(420.0f);
	if (UVerticalBoxSlot* InventorySectionSizeSlot = LeftColumn->AddChildToVerticalBox(InventorySectionSize))
	{
		InventorySectionSizeSlot->SetHorizontalAlignment(HAlign_Left);
	}

	UBorder* InventorySection = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("InventorySection"));
	InventorySection->SetBrushColor(UiSectionColor);
	InventorySection->SetPadding(FMargin(12.0f));
	InventorySectionSize->SetContent(InventorySection);

	UVerticalBox* LeftSectionBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("InventorySectionVBox"));
	InventorySection->SetContent(LeftSectionBox);

	USizeBox* InventoryGridScrollSize = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("InventoryGridScrollSize"));
	InventoryGridScrollSize->SetHeightOverride(396.0f);
	if (UVerticalBoxSlot* InventoryGridSlot = LeftSectionBox->AddChildToVerticalBox(InventoryGridScrollSize))
	{
		InventoryGridSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 8.0f));
	}

	UScrollBox* InventoryGridScroll = WidgetTree->ConstructWidget<UScrollBox>(UScrollBox::StaticClass(), TEXT("InventoryGridScroll"));
	InventoryGridScrollSize->SetContent(InventoryGridScroll);

	UUniformGridPanel* InventoryGrid = WidgetTree->ConstructWidget<UUniformGridPanel>(UUniformGridPanel::StaticClass(), TEXT("InventoryGrid"));
	InventoryGrid->SetMinDesiredSlotWidth(94.0f);
	InventoryGrid->SetMinDesiredSlotHeight(94.0f);
	InventoryGrid->SetSlotPadding(FMargin(0.0f));
	InventoryGridScroll->AddChild(InventoryGrid);

	TArray<int32> MatchingItemIndices;
	TArray<int32> EmptyIndices;
	MatchingItemIndices.Reserve(UFableSaveSubsystem::InventorySlotsPerCharacter);
	EmptyIndices.Reserve(UFableSaveSubsystem::InventorySlotsPerCharacter);

	for (int32 SlotIndex = 0; SlotIndex < UFableSaveSubsystem::InventorySlotsPerCharacter; ++SlotIndex)
	{
		const FString ItemId = InventorySlots.IsValidIndex(SlotIndex) ? InventorySlots[SlotIndex] : TEXT("");
		if (ItemId.IsEmpty())
		{
			EmptyIndices.Add(SlotIndex);
			continue;
		}

		if (ActiveInventoryCategory == CategoryAllAction || ResolveItemCategory(ItemId) == ActiveInventoryCategory)
		{
			MatchingItemIndices.Add(SlotIndex);
		}
	}

	constexpr int32 InventoryColumns = 7;
	constexpr int32 MinVisibleRows = 4;
	constexpr int32 MinVisibleSlots = InventoryColumns * MinVisibleRows;

	int32 DesiredVisibleSlots = FMath::Max(MinVisibleSlots, MatchingItemIndices.Num() + InventoryColumns); // one extra row of empties
	DesiredVisibleSlots = FMath::Min(DesiredVisibleSlots, UFableSaveSubsystem::InventorySlotsPerCharacter);
	if (DesiredVisibleSlots % InventoryColumns != 0)
	{
		const int32 RoundedUp = DesiredVisibleSlots + (InventoryColumns - (DesiredVisibleSlots % InventoryColumns));
		if (RoundedUp <= UFableSaveSubsystem::InventorySlotsPerCharacter)
		{
			DesiredVisibleSlots = RoundedUp;
		}
		else
		{
			DesiredVisibleSlots = FMath::Max(MinVisibleSlots, DesiredVisibleSlots - (DesiredVisibleSlots % InventoryColumns));
		}
	}

	TArray<int32> VisibleInventoryIndices;
	VisibleInventoryIndices.Reserve(DesiredVisibleSlots);
	VisibleInventoryIndices.Append(MatchingItemIndices);
	for (int32 Index : EmptyIndices)
	{
		if (VisibleInventoryIndices.Num() >= DesiredVisibleSlots)
		{
			break;
		}
		VisibleInventoryIndices.Add(Index);
	}

	for (int32 DisplayIndex = 0; DisplayIndex < VisibleInventoryIndices.Num(); ++DisplayIndex)
	{
		const int32 SlotIndex = VisibleInventoryIndices[DisplayIndex];
		const FName SlotId(*FString::Printf(TEXT("inv_%d"), SlotIndex));
		const FString ItemId = InventorySlots.IsValidIndex(SlotIndex) ? InventorySlots[SlotIndex] : TEXT("");

		UFableInventorySlotWidget* SlotWidget = WidgetTree->ConstructWidget<UFableInventorySlotWidget>(UFableInventorySlotWidget::StaticClass());
		SlotWidget->InitializeSlot(SlotId, TEXT(""), false);
		SlotWidget->SetItemData(ItemId, GetItemLabelForSlot(ItemId, false), GetItemIconForSlot(ItemId));
		SlotWidget->OnItemDrop.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotDropped);

		USizeBox* SlotSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		SlotSizeBox->SetWidthOverride(94.0f);
		SlotSizeBox->SetHeightOverride(94.0f);
		SlotSizeBox->SetContent(SlotWidget);

		if (UUniformGridSlot* GridSlot = InventoryGrid->AddChildToUniformGrid(SlotSizeBox, DisplayIndex / InventoryColumns, DisplayIndex % InventoryColumns))
		{
			GridSlot->SetHorizontalAlignment(HAlign_Left);
			GridSlot->SetVerticalAlignment(VAlign_Top);
		}

		SlotWidgets.Add(SlotId, SlotWidget);
	}

	UVerticalBox* RightColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("InventoryRightColumn"));
	if (UHorizontalBoxSlot* RightSlot = MainRow->AddChildToHorizontalBox(RightColumn))
	{
		RightSlot->SetHorizontalAlignment(HAlign_Left);
	}

	USizeBox* EquipmentSectionSize = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("EquipmentSectionSize"));
	EquipmentSectionSize->SetWidthOverride(308.0f);
	EquipmentSectionSize->SetHeightOverride(420.0f);
	if (UVerticalBoxSlot* EquipmentSectionSizeSlot = RightColumn->AddChildToVerticalBox(EquipmentSectionSize))
	{
		EquipmentSectionSizeSlot->SetHorizontalAlignment(HAlign_Left);
	}

	UBorder* EquipmentSection = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("EquipmentSection"));
	EquipmentSection->SetBrushColor(UiSectionColor);
	EquipmentSection->SetPadding(FMargin(12.0f));
	EquipmentSectionSize->SetContent(EquipmentSection);

	UVerticalBox* RightSectionBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("EquipmentSectionVBox"));
	EquipmentSection->SetContent(RightSectionBox);

	USizeBox* EquipmentGridSize = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("EquipmentGridSize"));
	EquipmentGridSize->SetWidthOverride(282.0f);
	EquipmentGridSize->SetHeightOverride(376.0f);
	if (UVerticalBoxSlot* EquipmentGridSizeSlot = RightSectionBox->AddChildToVerticalBox(EquipmentGridSize))
	{
		EquipmentGridSizeSlot->SetHorizontalAlignment(HAlign_Left);
	}

	UUniformGridPanel* EquipmentGrid = WidgetTree->ConstructWidget<UUniformGridPanel>(UUniformGridPanel::StaticClass(), TEXT("EquipmentGrid"));
	EquipmentGrid->SetMinDesiredSlotWidth(94.0f);
	EquipmentGrid->SetMinDesiredSlotHeight(94.0f);
	EquipmentGrid->SetSlotPadding(FMargin(0.0f));
	EquipmentGridSize->SetContent(EquipmentGrid);
	for (const FEquipmentLayoutCell& LayoutCell : EquipmentLayout)
	{
		const int32 SlotIndex = LayoutCell.LogicalIndex;
		const FName SlotId(*FString::Printf(TEXT("equip_%d"), SlotIndex));
		const FString ItemId = EquippedSlots.IsValidIndex(SlotIndex) ? EquippedSlots[SlotIndex] : TEXT("");

		UFableInventorySlotWidget* SlotWidget = WidgetTree->ConstructWidget<UFableInventorySlotWidget>(UFableInventorySlotWidget::StaticClass());
		SlotWidget->InitializeSlot(SlotId, EquipmentSlotNames.IsValidIndex(SlotIndex) ? EquipmentSlotNames[SlotIndex] : TEXT("Equip"), true);
		SlotWidget->SetItemData(ItemId, GetItemLabelForSlot(ItemId, true), GetItemIconForSlot(ItemId));
		SlotWidget->OnItemDrop.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotDropped);

		USizeBox* SlotSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		SlotSizeBox->SetWidthOverride(94.0f);
		SlotSizeBox->SetHeightOverride(94.0f);
		SlotSizeBox->SetContent(SlotWidget);

		if (UUniformGridSlot* GridSlot = EquipmentGrid->AddChildToUniformGrid(SlotSizeBox, LayoutCell.Row, LayoutCell.Col))
		{
			GridSlot->SetHorizontalAlignment(HAlign_Left);
			GridSlot->SetVerticalAlignment(VAlign_Top);
		}

		SlotWidgets.Add(SlotId, SlotWidget);
	}

}

void UFableCharacterMenuWidget::BuildSimpleInfoTab(const FString& Header, const FString& Body)
{
	auto AddLine = [&](const FString& Text, bool bMuted = false)
	{
		UTextBlock* Line = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Line->SetText(FText::FromString(Text));
		Line->SetAutoWrapText(true);
		Line->SetColorAndOpacity(FSlateColor(bMuted ? UiMutedTextColor : UiTextColor));
		if (UVerticalBoxSlot* LineSlot = ContentRoot->AddChildToVerticalBox(Line))
		{
			LineSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 10.0f));
		}
	};

	AddLine(Header, false);
	AddLine(Body, true);
}

void UFableCharacterMenuWidget::BuildSkillsTab()
{
	LoadSkillDefinitionsFromDataTable();

	TArray<FString> LearnedSkills;
	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		SaveSubsystem->TryGetActiveLearnedSkills(LearnedSkills);
	}

	if (LearnedSkills.Num() == 0)
	{
		BuildSimpleInfoTab(TEXT("Skills"), TEXT("No learned skills yet."));
		return;
	}

	if (ActiveSkillDetailsId.IsEmpty() || !LearnedSkills.Contains(ActiveSkillDetailsId))
	{
		ActiveSkillDetailsId = LearnedSkills[0];
	}

	TArray<EFableSkillCategory> AvailableCategories;
	for (const FString& SkillId : LearnedSkills)
	{
		const FFableSkillDefinitionTableRow* SkillRow = FindSkillDefinition(SkillId);
		if (SkillRow == nullptr)
		{
			continue;
		}

		AvailableCategories.AddUnique(SkillRow->Category);
	}

	UHorizontalBox* SkillCategoryRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("SkillCategoryRow"));
	if (UVerticalBoxSlot* SkillCategoryRowSlot = ContentRoot->AddChildToVerticalBox(SkillCategoryRow))
	{
		SkillCategoryRowSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 10.0f));
	}

	auto AddSkillCategoryButton = [&](const FString& Label, FName CategoryAction)
	{
		UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		Button->InitializeAction(CategoryAction);
		Button->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		Button->SetBackgroundColor(ActiveSkillCategory == CategoryAction ? UiButtonSelectedColor : UiButtonColor);

		UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Text->SetText(FText::FromString(Label));
		Text->SetColorAndOpacity(FSlateColor(UiTextColor));
		Text->SetJustification(ETextJustify::Center);
		FSlateFontInfo FontInfo = Text->GetFont();
		FontInfo.Size = 13;
		Text->SetFont(FontInfo);
		Button->AddChild(Text);
		if (UButtonSlot* TextSlot = Cast<UButtonSlot>(Text->Slot))
		{
			TextSlot->SetHorizontalAlignment(HAlign_Center);
			TextSlot->SetVerticalAlignment(VAlign_Center);
			TextSlot->SetPadding(FMargin(8.0f, 6.0f));
		}

		if (UHorizontalBoxSlot* HorizontalSlot = SkillCategoryRow->AddChildToHorizontalBox(Button))
		{
			HorizontalSlot->SetPadding(FMargin(0.0f, 0.0f, 6.0f, 0.0f));
		}
	};

	AddSkillCategoryButton(TEXT("All"), SkillCategoryAllAction);
	for (EFableSkillCategory Category : AvailableCategories)
	{
		AddSkillCategoryButton(EnumToString(Category), SkillCategoryActionFromEnum(Category));
	}

	TArray<FString> VisibleSkills;
	VisibleSkills.Reserve(LearnedSkills.Num());
	for (const FString& SkillId : LearnedSkills)
	{
		const FFableSkillDefinitionTableRow* SkillRow = FindSkillDefinition(SkillId);
		if (ActiveSkillCategory != SkillCategoryAllAction && SkillRow != nullptr && SkillCategoryActionFromEnum(SkillRow->Category) != ActiveSkillCategory)
		{
			continue;
		}

		if (ActiveSkillCategory != SkillCategoryAllAction && SkillRow == nullptr)
		{
			continue;
		}

		VisibleSkills.Add(SkillId);
	}

	if (VisibleSkills.Num() == 0)
	{
		ActiveSkillCategory = SkillCategoryAllAction;
		VisibleSkills = LearnedSkills;
	}

	if (ActiveSkillDetailsId.IsEmpty() || !VisibleSkills.Contains(ActiveSkillDetailsId))
	{
		ActiveSkillDetailsId = VisibleSkills.Num() > 0 ? VisibleSkills[0] : FString();
	}

	UHorizontalBox* MainRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("SkillsMainRow"));
	if (UVerticalBoxSlot* MainRowSlot = ContentRoot->AddChildToVerticalBox(MainRow))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		MainRowSlot->SetSize(FillSize);
	}

	UBorder* SkillListSection = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("SkillsListSection"));
	SkillListSection->SetBrushColor(UiSectionColor);
	SkillListSection->SetPadding(FMargin(8.0f));
	if (UHorizontalBoxSlot* ListSlot = MainRow->AddChildToHorizontalBox(SkillListSection))
	{
		FSlateChildSize ListSize;
		ListSize.SizeRule = ESlateSizeRule::Fill;
		ListSize.Value = 0.28f;
		ListSlot->SetSize(ListSize);
		ListSlot->SetPadding(FMargin(0.0f, 0.0f, 12.0f, 0.0f));
	}

	UScrollBox* SkillsListScroll = WidgetTree->ConstructWidget<UScrollBox>(UScrollBox::StaticClass(), TEXT("SkillsListScroll"));
	SkillListSection->SetContent(SkillsListScroll);

	UVerticalBox* SkillsListVBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("SkillsListVBox"));
	SkillsListScroll->AddChild(SkillsListVBox);

	for (int32 SkillIndex = 0; SkillIndex < VisibleSkills.Num(); ++SkillIndex)
	{
		const FString& SkillId = VisibleSkills[SkillIndex];
		const FFableSkillDefinitionTableRow* SkillRow = FindSkillDefinition(SkillId);
		const bool bSelected = SkillId == ActiveSkillDetailsId;
		const FString Token = (SkillRow != nullptr && !SkillRow->IconToken.IsEmpty())
			? SkillRow->IconToken
			: BuildIconToken(SkillRow != nullptr && !SkillRow->DisplayName.IsEmpty() ? SkillRow->DisplayName : SkillId);

		UBorder* RowBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
		RowBorder->SetBrushColor(bSelected ? UiButtonSelectedColor : UiButtonColor);
		RowBorder->SetPadding(FMargin(6.0f));
		if (UVerticalBoxSlot* RowSlot = SkillsListVBox->AddChildToVerticalBox(RowBorder))
		{
			RowSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 6.0f));
		}

		UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass());
		RowBorder->SetContent(Row);

		const FName SlotId(*FString::Printf(TEXT("skill_%d"), SkillIndex));
		UFableInventorySlotWidget* SkillSlot = WidgetTree->ConstructWidget<UFableInventorySlotWidget>(UFableInventorySlotWidget::StaticClass());
		SkillSlot->InitializeSlot(SlotId, TEXT(""), false);
		UTexture2D* SkillIcon = (SkillRow != nullptr && !SkillRow->SkillIconTexture.IsNull())
			? SkillRow->SkillIconTexture.LoadSynchronous()
			: nullptr;
		SkillSlot->SetItemData(FString::Printf(TEXT("skill:%s"), *SkillId), Token, SkillIcon);

		USizeBox* SlotSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		SlotSizeBox->SetWidthOverride(60.0f);
		SlotSizeBox->SetHeightOverride(60.0f);
		SlotSizeBox->SetContent(SkillSlot);
		if (UHorizontalBoxSlot* SlotHBox = Row->AddChildToHorizontalBox(SlotSizeBox))
		{
			SlotHBox->SetPadding(FMargin(0.0f, 0.0f, 8.0f, 0.0f));
		}

		const FName SkillSelectAction(*FString::Printf(TEXT("%s%d"), SkillSelectActionPrefix, SkillIndex));
		SkillRowActions.Add(SkillSelectAction, SkillId);
		UFableActionButton* RowTextButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		RowTextButton->InitializeAction(SkillSelectAction);
		RowTextButton->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		RowTextButton->SetBackgroundColor(FLinearColor::Transparent);
		if (UHorizontalBoxSlot* TextButtonSlot = Row->AddChildToHorizontalBox(RowTextButton))
		{
			FSlateChildSize FillSize;
			FillSize.SizeRule = ESlateSizeRule::Fill;
			FillSize.Value = 1.0f;
			TextButtonSlot->SetSize(FillSize);
			TextButtonSlot->SetVerticalAlignment(VAlign_Fill);
		}

		UVerticalBox* RowText = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass());
		RowText->SetVisibility(ESlateVisibility::HitTestInvisible);
		RowTextButton->AddChild(RowText);

		UTextBlock* NameText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		NameText->SetText(FText::FromString(SkillRow != nullptr && !SkillRow->DisplayName.IsEmpty() ? SkillRow->DisplayName : HumanizeToken(SkillId)));
		NameText->SetColorAndOpacity(FSlateColor(UiTextColor));
		RowText->AddChildToVerticalBox(NameText);

		UTextBlock* Subtitle = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Subtitle->SetText(FText::FromString(SkillRow != nullptr ? SkillRow->Summary : TEXT("No DataTable definition yet")));
		Subtitle->SetColorAndOpacity(FSlateColor(UiMutedTextColor));
		Subtitle->SetAutoWrapText(true);
		FSlateFontInfo SubtitleFont = Subtitle->GetFont();
		SubtitleFont.Size = 11;
		Subtitle->SetFont(SubtitleFont);
		RowText->AddChildToVerticalBox(Subtitle);
	}

	UBorder* DetailsSection = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("SkillDetailsSection"));
	DetailsSection->SetBrushColor(UiSectionColor);
	DetailsSection->SetPadding(FMargin(12.0f));
	if (UHorizontalBoxSlot* DetailsSlot = MainRow->AddChildToHorizontalBox(DetailsSection))
	{
		FSlateChildSize DetailsSize;
		DetailsSize.SizeRule = ESlateSizeRule::Fill;
		DetailsSize.Value = 0.72f;
		DetailsSlot->SetSize(DetailsSize);
	}

	UScrollBox* DetailsScroll = WidgetTree->ConstructWidget<UScrollBox>(UScrollBox::StaticClass(), TEXT("SkillDetailsScroll"));
	DetailsSection->SetContent(DetailsScroll);

	UVerticalBox* DetailsVBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("SkillDetailsVBox"));
	DetailsScroll->AddChild(DetailsVBox);

	const FFableSkillDefinitionTableRow* SelectedSkill = FindSkillDefinition(ActiveSkillDetailsId);
	const FString SelectedSkillName = SelectedSkill != nullptr && !SelectedSkill->DisplayName.IsEmpty()
		? SelectedSkill->DisplayName
		: HumanizeToken(ActiveSkillDetailsId);

	auto AddDetailLine = [&](const FString& Label, const FString& Value, bool bMuted = false, int32 FontSize = 13)
	{
		if (Value.IsEmpty())
		{
			return;
		}

		UTextBlock* Line = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Line->SetText(FText::FromString(Label.IsEmpty() ? Value : FString::Printf(TEXT("%s: %s"), *Label, *Value)));
		Line->SetAutoWrapText(true);
		Line->SetColorAndOpacity(FSlateColor(bMuted ? UiMutedTextColor : UiTextColor));
		FSlateFontInfo Font = Line->GetFont();
		Font.Size = FontSize;
		Line->SetFont(Font);
		if (UVerticalBoxSlot* LineSlot = DetailsVBox->AddChildToVerticalBox(Line))
		{
			LineSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 6.0f));
		}
	};

	AddDetailLine(TEXT(""), SelectedSkillName, false, 18);

	if (SelectedSkill == nullptr)
	{
		AddDetailLine(TEXT("Status"), TEXT("Missing DataTable row for this learned skill"), true);
		return;
	}

	AddDetailLine(TEXT("Summary"), SelectedSkill->Summary, true);
	AddDetailLine(TEXT("Description"), SelectedSkill->Description, true);
	AddDetailLine(TEXT("Category"), EnumToString(SelectedSkill->Category));
	AddDetailLine(TEXT("Type"), EnumToString(SelectedSkill->SkillType));
	AddDetailLine(TEXT("Targeting"), EnumToString(SelectedSkill->TargetingMode));

	FString CostText = SelectedSkill->ResourceType == EFableSkillResourceType::None
		? TEXT("No resource cost")
		: FString::Printf(TEXT("%.0f %s"), SelectedSkill->ResourceCost, *EnumToString(SelectedSkill->ResourceType));
	AddDetailLine(TEXT("Cost"), CostText);
	AddDetailLine(TEXT("Cooldown"), FString::Printf(TEXT("%.1fs"), SelectedSkill->CooldownSeconds));
	AddDetailLine(TEXT("Cast Time"), FString::Printf(TEXT("%.1fs"), SelectedSkill->CastTimeSeconds));
	AddDetailLine(TEXT("Range"), FString::Printf(TEXT("%.0f"), SelectedSkill->RangeUnits));
	if (SelectedSkill->RadiusUnits > 0.0f)
	{
		AddDetailLine(TEXT("Radius"), FString::Printf(TEXT("%.0f"), SelectedSkill->RadiusUnits));
	}

	FString ScalingText = SelectedSkill->ScalingPrimaryStat.IsEmpty()
		? TEXT("None")
		: FString::Printf(TEXT("%s x%.2f"), *HumanizeToken(SelectedSkill->ScalingPrimaryStat), SelectedSkill->ScalingPrimaryCoefficient);
	if (!SelectedSkill->ScalingSecondaryStat.IsEmpty())
	{
		ScalingText += FString::Printf(TEXT(", %s x%.2f"), *HumanizeToken(SelectedSkill->ScalingSecondaryStat), SelectedSkill->ScalingSecondaryCoefficient);
	}
	AddDetailLine(TEXT("Scaling"), ScalingText);
	AddDetailLine(TEXT("Tags"), JoinHumanizedList(SelectedSkill->TagsCsv));
	AddDetailLine(TEXT("Effects"), JoinHumanizedList(SelectedSkill->EffectIdsCsv));
	AddDetailLine(TEXT("Synergy Rules"), JoinHumanizedList(SelectedSkill->SynergyRuleIdsCsv));
	AddDetailLine(TEXT("Discovery Rules"), JoinHumanizedList(SelectedSkill->DiscoveryRuleIdsCsv));
	AddDetailLine(TEXT("Learning Sources"), JoinHumanizedList(SelectedSkill->LearningSourcesCsv));
	AddDetailLine(TEXT("Witness Skills"), JoinHumanizedList(SelectedSkill->WitnessSkillIdsCsv));
	AddDetailLine(TEXT("Books"), JoinHumanizedList(SelectedSkill->BookIdsCsv));
	AddDetailLine(TEXT("Character Animation"), SelectedSkill->CharacterAnimationAsset.ToSoftObjectPath().ToString(), true);
	AddDetailLine(TEXT("Effect Animation"), SelectedSkill->EffectAnimationAsset.ToString(), true);
	AddDetailLine(
		TEXT("Latent Mastery"),
		FString::Printf(TEXT("Dormant -> Stirring %d, Awakening %d, Manifested %d"),
			SelectedSkill->StirringProgressThreshold,
			SelectedSkill->AwakeningProgressThreshold,
			SelectedSkill->ManifestedProgressThreshold));
}

void UFableCharacterMenuWidget::LoadSkillDefinitionsFromDataTable()
{
	if (bSkillDefinitionsLoaded)
	{
		return;
	}

	SkillDefinitions.Reset();

	if (UDataTable* SkillsTable = LoadObject<UDataTable>(nullptr, SkillsDataTablePath))
	{
		static const FString ContextString(TEXT("UFableCharacterMenuWidget::LoadSkillDefinitionsFromDataTable"));
		TArray<FFableSkillDefinitionTableRow*> Rows;
		SkillsTable->GetAllRows(ContextString, Rows);

		for (const FFableSkillDefinitionTableRow* Row : Rows)
		{
			if (Row == nullptr || Row->SkillId.IsEmpty())
			{
				continue;
			}

			SkillDefinitions.Add(Row->SkillId, *Row);
		}
	}
	else
	{
		UE_LOG(LogFableForge, Warning, TEXT("Skills DataTable not found at '%s'."), SkillsDataTablePath);
	}

	bSkillDefinitionsLoaded = true;
}

const FFableSkillDefinitionTableRow* UFableCharacterMenuWidget::FindSkillDefinition(const FString& SkillId) const
{
	return SkillDefinitions.Find(SkillId);
}

void UFableCharacterMenuWidget::LoadInventoryFromSave()
{
	if (bInventoryLoaded)
	{
		return;
	}

	InventorySlots.SetNum(UFableSaveSubsystem::InventorySlotsPerCharacter);
	EquippedSlots.SetNum(UFableSaveSubsystem::EquipmentSlotsPerCharacter);

	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		TArray<FString> SavedInventory;
		TArray<FString> SavedEquipment;
		if (SaveSubsystem->TryGetActiveInventory(SavedInventory, SavedEquipment))
		{
			InventorySlots = SavedInventory;
			EquippedSlots = SavedEquipment;
		}
	}

	if (InventorySlots.Num() != UFableSaveSubsystem::InventorySlotsPerCharacter)
	{
		InventorySlots.SetNum(UFableSaveSubsystem::InventorySlotsPerCharacter);
	}
	if (EquippedSlots.Num() != UFableSaveSubsystem::EquipmentSlotsPerCharacter)
	{
		EquippedSlots.SetNum(UFableSaveSubsystem::EquipmentSlotsPerCharacter);
	}

	bInventoryLoaded = true;
}

void UFableCharacterMenuWidget::SaveInventoryToSaveSubsystem() const
{
	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		SaveSubsystem->SetActiveInventory(InventorySlots, EquippedSlots);
	}
}

void UFableCharacterMenuWidget::LoadItemDefinitionsFromUnityJson()
{
	if (bItemDefinitionsLoaded)
	{
		return;
	}

	ItemDefinitions.Reset();
	IconTextureCache.Reset();

	auto AddDefinition = [&](const FFableUiItemDefinition& Definition)
	{
		if (Definition.Id.IsEmpty())
		{
			return;
		}

		ItemDefinitions.Add(Definition.Id, Definition);
	};

	auto LoadDefinitionsFromTable = [&](const TCHAR* TablePath, const TCHAR* TableLabel) -> bool
	{
		UDataTable* ItemDefinitionsTable = LoadObject<UDataTable>(nullptr, TablePath);
		if (ItemDefinitionsTable == nullptr)
		{
			UE_LOG(LogFableForge, Warning, TEXT("%s DataTable not found at '%s'."), TableLabel, TablePath);
			return false;
		}

		const FString ContextString = FString::Printf(TEXT("UFableCharacterMenuWidget::LoadItemDefinitionsFromUnityJson(%s)"), TableLabel);
		TArray<FFableItemDefinitionTableRow*> Rows;
		ItemDefinitionsTable->GetAllRows(ContextString, Rows);

		const FString Label = TableLabel;
		const bool bIsWeaponsTable = Label.Equals(TEXT("Weapons"));
		const bool bIsArmorTable = Label.Equals(TEXT("Armor"));

		for (const FFableItemDefinitionTableRow* Row : Rows)
		{
			if (Row == nullptr)
			{
				continue;
			}

			FFableUiItemDefinition Definition;
			Definition.Id = Row->ItemId;
			if (Definition.Id.IsEmpty())
			{
				continue;
			}

			Definition.Name = !Row->DisplayName.IsEmpty() ? Row->DisplayName : Definition.Id;
			Definition.Category = CategoryFromType(Row->Type);
			Definition.bStackable = Row->bStackable;
			Definition.bEquipable = Row->bEquipable;
			if (bIsWeaponsTable)
			{
				const FString LowerId = Definition.Id.ToLower();
				Definition.EquipmentSlot = (LowerId.Contains(TEXT("bow")) || LowerId.Contains(TEXT("crossbow"))) ? 11 : 0;
			}
			else if (bIsArmorTable)
			{
				const FString LowerId = Definition.Id.ToLower();
				if (LowerId.EndsWith(TEXT("_offhand")) || LowerId.EndsWith(TEXT("_off_hand")) || LowerId.Contains(TEXT("shield")))
				{
					Definition.EquipmentSlot = 1;
				}
				else if (LowerId.EndsWith(TEXT("_back")))
				{
					Definition.EquipmentSlot = 7;
				}
				else if (LowerId.EndsWith(TEXT("_neck")) || LowerId.Contains(TEXT("amulet")) || LowerId.Contains(TEXT("necklace")))
				{
					Definition.EquipmentSlot = 8;
				}
				else if (LowerId.Contains(TEXT("ring")))
				{
					Definition.EquipmentSlot = 9;
				}
				else
				{
					FString Left;
					FString Right;
					Definition.EquipmentSlot = Definition.Id.Split(TEXT("_"), &Left, &Right, ESearchCase::IgnoreCase, ESearchDir::FromEnd)
						? ArmorSlotIndexFromString(Right)
						: INDEX_NONE;
				}
			}
			else
			{
				Definition.EquipmentSlot = INDEX_NONE;
			}
			Definition.IconAssetPath = Row->IconTexture.ToSoftObjectPath().ToString();
			Definition.IconToken = BuildIconToken(Definition.Name);
			Definition.ModelPath.Reset();
			Definition.ModelPathMale.Reset();
			Definition.ModelPathFemale.Reset();
			AddDefinition(Definition);
		}

		return true;
	};

	const bool bLoadedAny =
		LoadDefinitionsFromTable(ItemsDataTablePath, TEXT("Items")) |
		LoadDefinitionsFromTable(WeaponsDataTablePath, TEXT("Weapons")) |
		LoadDefinitionsFromTable(ArmorDataTablePath, TEXT("Armor"));

	if (!bLoadedAny)
	{
		UE_LOG(LogFableForge, Warning, TEXT("No item definition DataTables were loaded. Expected '%s', '%s', '%s'."),
			ItemsDataTablePath, WeaponsDataTablePath, ArmorDataTablePath);
	}

	bItemDefinitionsLoaded = true;
}

void UFableCharacterMenuWidget::RefreshInventorySlotWidgets()
{
	for (TPair<FName, TObjectPtr<UFableInventorySlotWidget>>& Pair : SlotWidgets)
	{
		const FName SlotId = Pair.Key;
		UFableInventorySlotWidget* SlotWidget = Pair.Value;
		if (SlotWidget == nullptr)
		{
			continue;
		}

		bool bEquipmentSlot = false;
		int32 SlotIndex = INDEX_NONE;
		if (!ResolveSlotAddress(SlotId, bEquipmentSlot, SlotIndex))
		{
			continue;
		}

		const TArray<FString>& SourceArray = bEquipmentSlot ? EquippedSlots : InventorySlots;
		if (!SourceArray.IsValidIndex(SlotIndex))
		{
			continue;
		}

		const FString ItemId = SourceArray[SlotIndex];
		if (!bEquipmentSlot && ActiveInventoryCategory != CategoryAllAction && !ItemId.IsEmpty() && ResolveItemCategory(ItemId) != ActiveInventoryCategory)
		{
			SlotWidget->SetItemData(TEXT(""), TEXT(""), nullptr);
			continue;
		}

		SlotWidget->SetItemData(ItemId, GetItemLabelForSlot(ItemId, bEquipmentSlot), GetItemIconForSlot(ItemId));
	}
}

bool UFableCharacterMenuWidget::ResolveSlotAddress(FName SlotId, bool& bOutEquipmentSlot, int32& OutSlotIndex) const
{
	bOutEquipmentSlot = false;
	OutSlotIndex = INDEX_NONE;

	const FString SlotString = SlotId.ToString();
	FString Prefix;
	FString IndexString;
	if (!SlotString.Split(TEXT("_"), &Prefix, &IndexString, ESearchCase::CaseSensitive, ESearchDir::FromEnd))
	{
		return false;
	}

	int32 ParsedIndex = INDEX_NONE;
	if (!LexTryParseString(ParsedIndex, *IndexString))
	{
		return false;
	}

	if (Prefix == TEXT("equip"))
	{
		bOutEquipmentSlot = true;
		OutSlotIndex = ParsedIndex;
		return true;
	}

	if (Prefix == TEXT("inv"))
	{
		bOutEquipmentSlot = false;
		OutSlotIndex = ParsedIndex;
		return true;
	}

	return false;
}

bool UFableCharacterMenuWidget::IsItemAllowedInEquipmentSlot(const FString& ItemId, int32 EquipmentSlotIndex) const
{
	if (ItemId.IsEmpty())
	{
		return true;
	}

	const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId);
	if (Definition == nullptr || !Definition->bEquipable)
	{
		return false;
	}

	if (Definition->EquipmentSlot == EquipmentSlotIndex)
	{
		return true;
	}

	// Allow rings in either ring slot.
	if (IsRingEquipmentSlotIndex(Definition->EquipmentSlot) && IsRingEquipmentSlotIndex(EquipmentSlotIndex))
	{
		return true;
	}

	return false;
}

FString UFableCharacterMenuWidget::GetItemLabelForSlot(const FString& ItemId, bool bEquipmentSlot) const
{
	if (ItemId.IsEmpty())
	{
		return TEXT("");
	}

	if (const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId))
	{
		if (!Definition->Name.IsEmpty())
		{
			return Definition->Name;
		}
	}

	return bEquipmentSlot ? ItemId : ItemId;
}

UTexture2D* UFableCharacterMenuWidget::GetItemIconForSlot(const FString& ItemId)
{
	if (ItemId.IsEmpty())
	{
		return nullptr;
	}

	if (TObjectPtr<UTexture2D>* CachedTexture = IconTextureCache.Find(ItemId))
	{
		return CachedTexture->Get();
	}

	const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId);
	if (Definition == nullptr || Definition->IconAssetPath.IsEmpty())
	{
		IconTextureCache.Add(ItemId, nullptr);
		return nullptr;
	}

	UTexture2D* Texture = LoadObject<UTexture2D>(nullptr, *Definition->IconAssetPath);
	IconTextureCache.Add(ItemId, Texture);
	return Texture;
}

FName UFableCharacterMenuWidget::ResolveItemCategory(const FString& ItemId) const
{
	if (ItemId.IsEmpty())
	{
		return CategoryMiscAction;
	}

	if (const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId))
	{
		return Definition->Category;
	}

	return CategoryMiscAction;
}

void UFableCharacterMenuWidget::HandleInventorySlotDropped(FName FromSlotId, FName ToSlotId, const FString& PayloadId, const FString& PayloadLabel)
{
	(void)PayloadId;
	(void)PayloadLabel;

	bool bFromEquipment = false;
	int32 FromIndex = INDEX_NONE;
	bool bToEquipment = false;
	int32 ToIndex = INDEX_NONE;

	if (!ResolveSlotAddress(FromSlotId, bFromEquipment, FromIndex) || !ResolveSlotAddress(ToSlotId, bToEquipment, ToIndex))
	{
		return;
	}

	TArray<FString>& FromArray = bFromEquipment ? EquippedSlots : InventorySlots;
	TArray<FString>& ToArray = bToEquipment ? EquippedSlots : InventorySlots;
	if (!FromArray.IsValidIndex(FromIndex) || !ToArray.IsValidIndex(ToIndex))
	{
		return;
	}

	const FString SourceItemId = FromArray[FromIndex];
	const FString DestinationItemId = ToArray[ToIndex];
	if (SourceItemId.IsEmpty())
	{
		return;
	}

	if (bToEquipment && !IsItemAllowedInEquipmentSlot(SourceItemId, ToIndex))
	{
		return;
	}

	if (bFromEquipment && !DestinationItemId.IsEmpty() && !IsItemAllowedInEquipmentSlot(DestinationItemId, FromIndex))
	{
		return;
	}

	const FString TempValue = FromArray[FromIndex];
	FromArray[FromIndex] = ToArray[ToIndex];
	ToArray[ToIndex] = TempValue;

	if (ActiveTab == TEXT("inventory"))
	{
		QueueTabContentRebuild();
	}
	else
	{
		RefreshInventorySlotWidgets();
	}
	SaveInventoryToSaveSubsystem();
}

void UFableCharacterMenuWidget::HandleActionClicked(FName ActionId)
{
	if (ActionId == CloseMenuAction)
	{
		if (AFableForgePlayerController* ForgePC = Cast<AFableForgePlayerController>(GetOwningPlayer()))
		{
			if (UWorld* World = GetWorld())
			{
				World->GetTimerManager().SetTimerForNextTick(FTimerDelegate::CreateUObject(ForgePC, &AFableForgePlayerController::ToggleCharacterMenu));
			}
			else
			{
				ForgePC->ToggleCharacterMenu();
			}
		}
		else if (UWorld* World = GetWorld())
		{
			World->GetTimerManager().SetTimerForNextTick(FTimerDelegate::CreateUObject(this, &UFableCharacterMenuWidget::Close));
		}
		else
		{
			Close();
		}
		return;
	}

	if (ActionId == InventoryAction)
	{
		ActiveTab = TEXT("inventory");
		QueueTabContentRebuild();
		return;
	}

	if (ActionId == SkillsAction)
	{
		ActiveTab = TEXT("skills");
		QueueTabContentRebuild();
		return;
	}

	if (ActionId == CompanionsAction)
	{
		ActiveTab = TEXT("companions");
		QueueTabContentRebuild();
		return;
	}

	if (ActionId == BuildAction)
	{
		ActiveTab = TEXT("build");
		QueueTabContentRebuild();
		return;
	}

	if (ActionId == CategoryAllAction || ActionId == CategoryWeaponsAction || ActionId == CategoryArmorAction || ActionId == CategoryConsumablesAction || ActionId == CategoryMiscAction || ActionId == CategoryKeyItemsAction)
	{
		ActiveInventoryCategory = ActionId;
		if (ActiveTab == TEXT("inventory"))
		{
			QueueTabContentRebuild();
		}
		return;
	}

	FName SkillCategoryAction;
	if (TryParseSkillCategoryAction(ActionId, SkillCategoryAction))
	{
		ActiveSkillCategory = SkillCategoryAction;
		if (ActiveTab == TEXT("skills"))
		{
			QueueTabContentRebuild();
		}
		return;
	}

	if (const FString* SkillId = SkillRowActions.Find(ActionId))
	{
		if (!SkillId->IsEmpty() && *SkillId != ActiveSkillDetailsId)
		{
			ActiveSkillDetailsId = *SkillId;
			QueueTabContentRebuild();
		}
	}
}

void UFableCharacterMenuWidget::HandleSkillSlotHovered(FName SlotId, const FString& PayloadId)
{
	(void)SlotId;

	if (ActiveTab != TEXT("skills") || PayloadId.IsEmpty())
	{
		return;
	}

	FString SkillId = PayloadId;
	SkillId.RemoveFromStart(TEXT("skill:"));
	if (SkillId.IsEmpty() || SkillId == ActiveSkillDetailsId)
	{
		return;
	}

	ActiveSkillDetailsId = SkillId;
	QueueTabContentRebuild();
}

void UFableCharacterMenuWidget::HandleSkillSlotClicked(FName SlotId, const FString& PayloadId)
{
	(void)SlotId;

	if (ActiveTab != TEXT("skills") || PayloadId.IsEmpty())
	{
		return;
	}

	FString SkillId = PayloadId;
	SkillId.RemoveFromStart(TEXT("skill:"));
	if (SkillId.IsEmpty() || SkillId == ActiveSkillDetailsId)
	{
		return;
	}

	ActiveSkillDetailsId = SkillId;
	QueueTabContentRebuild();
}
