#include "RPG/UI/FablePartyHudWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/ButtonSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/ProgressBar.h"
#include "Components/SizeBox.h"
#include "Components/Spacer.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Engine/GameViewportClient.h"
#include "FableForgePlayerController.h"
#include "Misc/FileHelper.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "RPG/UI/FableActionButton.h"
#include "RPG/UI/FableActionBarWidget.h"
#include "RPG/UI/FableCharacterMenuWidget.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace
{
	const FName ToggleSettingsAction = TEXT("toggle_settings");
	const FName OpenSaveAction = TEXT("open_save");
	const FName OpenLoadAction = TEXT("open_load");
	const FName QuitToMainMenuAction = TEXT("quit_to_main_menu");
	const FName AddHorizontalActionBarAction = TEXT("add_horizontal_action_bar");
	const FName AddVerticalActionBarAction = TEXT("add_vertical_action_bar");
	const FName ConfirmDeleteActionBarAction = TEXT("confirm_delete_action_bar");
	const FName CancelDeleteActionBarAction = TEXT("cancel_delete_action_bar");
	const FName OpenCharacterMenuAction = TEXT("open_character_menu");
	const FName CloseModalAction = TEXT("close_modal");

	const FString UnityItemsPath = TEXT("/Users/scottlandes/Projects/Unity/FableForge/Assets/Resources/Prefabs/Objects/items.json");
	const FString UnityWeaponsPath = TEXT("/Users/scottlandes/Projects/Unity/FableForge/Assets/Resources/Prefabs/Objects/weapons.json");
	const FString UnityArmorPath = TEXT("/Users/scottlandes/Projects/Unity/FableForge/Assets/Resources/Prefabs/Objects/armor.json");

	const FLinearColor UiBackdropColor(0.0f, 0.0f, 0.0f, 0.62f);
	const FLinearColor UiPanelColor(0.01f, 0.01f, 0.01f, 0.96f);
	const FLinearColor UiTransparentColor(0.0f, 0.0f, 0.0f, 0.0f);
	const FLinearColor UiCardColor(0.0f, 0.0f, 0.0f, 0.82f);
	const FLinearColor UiButtonColor(0.05f, 0.05f, 0.05f, 1.0f);
	const FLinearColor UiButtonDisabledColor(0.03f, 0.03f, 0.03f, 0.75f);
	const FLinearColor UiTextColor(0.95f, 0.95f, 0.95f, 1.0f);
	const FLinearColor UiMutedTextColor(0.72f, 0.72f, 0.72f, 1.0f);
	const FLinearColor UiHealthColor(0.85f, 0.2f, 0.2f, 1.0f);
	const FLinearColor UiManaColor(0.24f, 0.45f, 0.95f, 1.0f);
	const FLinearColor UiExperienceColor(0.87f, 0.71f, 0.2f, 1.0f);
}

TSharedRef<SWidget> UFablePartyHudWidget::RebuildWidget()
{
	Rebuild();
	return Super::RebuildWidget();
}

void UFablePartyHudWidget::NativeConstruct()
{
	Super::NativeConstruct();
	RefreshFromSaveData();
}

void UFablePartyHudWidget::SetCharacterMenuWidget(UFableCharacterMenuWidget* InCharacterMenuWidget)
{
	CharacterMenuWidget = InCharacterMenuWidget;
}

void UFablePartyHudWidget::RefreshFromSaveData()
{
	UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (SaveSubsystem == nullptr)
	{
		return;
	}

	if (ItemTypeLookup.Num() == 0)
	{
		auto LoadJsonRoot = [](const FString& Path, TSharedPtr<FJsonObject>& OutRoot) -> bool
		{
			FString JsonText;
			if (!FFileHelper::LoadFileToString(JsonText, *Path))
			{
				return false;
			}

			const TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(JsonText);
			return FJsonSerializer::Deserialize(Reader, OutRoot) && OutRoot.IsValid();
		};

		auto AddArrayTypes = [&](const FString& Path, const TCHAR* ArrayName, const FString& TypeName)
		{
			TSharedPtr<FJsonObject> RootObject;
			if (!LoadJsonRoot(Path, RootObject))
			{
				return;
			}

			const TArray<TSharedPtr<FJsonValue>>* Entries = nullptr;
			if (!RootObject->TryGetArrayField(ArrayName, Entries) || Entries == nullptr)
			{
				return;
			}

			for (const TSharedPtr<FJsonValue>& Entry : *Entries)
			{
				const TSharedPtr<FJsonObject> EntryObject = Entry.IsValid() ? Entry->AsObject() : nullptr;
				if (!EntryObject.IsValid())
				{
					continue;
				}

				FString Id;
				if (EntryObject->TryGetStringField(TEXT("id"), Id) && !Id.IsEmpty())
				{
					FString Type = TypeName;
					EntryObject->TryGetStringField(TEXT("type"), Type);
					ItemTypeLookup.Add(Id, Type.ToLower());
				}
			}
		};

		AddArrayTypes(UnityItemsPath, TEXT("items"), TEXT("item"));
		AddArrayTypes(UnityWeaponsPath, TEXT("weapons"), TEXT("weapon"));
		AddArrayTypes(UnityArmorPath, TEXT("armor"), TEXT("armor"));
	}

	FFableCharacterProfile ActiveProfile;
	if (!SaveSubsystem->TryGetActiveCharacterProfile(ActiveProfile))
	{
		FFableCharacterProfile EmptyProfile;
		EmptyProfile.CharacterName = TEXT("No Active Character");
		EmptyProfile.HealthPercent = 0.0f;
		EmptyProfile.ManaPercent = 0.0f;
		EmptyProfile.ExperiencePercent = 0.0f;
		RebuildPartyMembers(EmptyProfile);
		ActionBars.Reset();
		RebuildActionBars();
		return;
	}

	ActionBars = ActiveProfile.ActionBars;
	RebuildPartyMembers(ActiveProfile);
	RebuildActionBars();
}

void UFablePartyHudWidget::Rebuild()
{
	if (WidgetTree == nullptr)
	{
		return;
	}

	ActionCounter = 0;
	CharacterActionMap.Reset();
	SlotActionMap.Reset();

	UCanvasPanel* Root = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("PartyHUDRoot"));
	WidgetTree->RootWidget = Root;

	ActionBarsCanvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("ActionBarsCanvas"));
	if (UCanvasPanelSlot* ActionBarsCanvasSlot = Root->AddChildToCanvas(ActionBarsCanvas))
	{
		ActionBarsCanvasSlot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
		ActionBarsCanvasSlot->SetOffsets(FMargin(0.0f));
	}

	UBorder* PartyPanel = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("PartyPanel"));
	PartyPanel->SetBrushColor(UiTransparentColor);
	PartyPanel->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	if (UCanvasPanelSlot* PartySlot = Root->AddChildToCanvas(PartyPanel))
	{
		PartySlot->SetAnchors(FAnchors(0.0f, 0.0f));
		PartySlot->SetAlignment(FVector2D(0.0f, 0.0f));
		PartySlot->SetPosition(FVector2D(16.0f, 16.0f));
		PartySlot->SetSize(FVector2D(360.0f, 320.0f));
	}

	PartyMembersBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("PartyMembers"));
	PartyPanel->SetContent(PartyMembersBox);

	UFableActionButton* SettingsButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass(), TEXT("SettingsButton"));
	SettingsButton->InitializeAction(ToggleSettingsAction);
	SettingsButton->OnActionClicked.AddDynamic(this, &UFablePartyHudWidget::HandleActionClicked);
	SettingsButton->SetBackgroundColor(UiButtonColor);

	UTextBlock* SettingsText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	SettingsText->SetText(FText::FromString(TEXT("Settings")));
	SettingsText->SetColorAndOpacity(FSlateColor(UiTextColor));
	SettingsText->SetJustification(ETextJustify::Center);
	{
		FSlateFontInfo FontInfo = SettingsText->GetFont();
		FontInfo.Size = 14;
		SettingsText->SetFont(FontInfo);
	}
	SettingsButton->AddChild(SettingsText);
	if (UButtonSlot* ButtonSlot = Cast<UButtonSlot>(SettingsText->Slot))
	{
		ButtonSlot->SetHorizontalAlignment(HAlign_Center);
		ButtonSlot->SetVerticalAlignment(VAlign_Center);
		ButtonSlot->SetPadding(FMargin(4.0f, 3.0f));
	}

	if (UCanvasPanelSlot* SettingsButtonSlot = Root->AddChildToCanvas(SettingsButton))
	{
		SettingsButtonSlot->SetAnchors(FAnchors(1.0f, 0.0f));
		SettingsButtonSlot->SetAlignment(FVector2D(1.0f, 0.0f));
		SettingsButtonSlot->SetPosition(FVector2D(-16.0f, 16.0f));
		SettingsButtonSlot->SetSize(FVector2D(144.0f, 34.0f));
	}

	UFableActionButton* CharacterButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass(), TEXT("CharacterButton"));
	CharacterButton->InitializeAction(OpenCharacterMenuAction);
	CharacterButton->OnActionClicked.AddDynamic(this, &UFablePartyHudWidget::HandleActionClicked);
	CharacterButton->SetBackgroundColor(UiButtonColor);

	UTextBlock* CharacterText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	CharacterText->SetText(FText::FromString(TEXT("Character")));
	CharacterText->SetColorAndOpacity(FSlateColor(UiTextColor));
	CharacterText->SetJustification(ETextJustify::Center);
	{
		FSlateFontInfo FontInfo = CharacterText->GetFont();
		FontInfo.Size = 14;
		CharacterText->SetFont(FontInfo);
	}
	CharacterButton->AddChild(CharacterText);
	if (UButtonSlot* CharacterTextSlot = Cast<UButtonSlot>(CharacterText->Slot))
	{
		CharacterTextSlot->SetHorizontalAlignment(HAlign_Center);
		CharacterTextSlot->SetVerticalAlignment(VAlign_Center);
		CharacterTextSlot->SetPadding(FMargin(4.0f, 3.0f));
	}

	if (UCanvasPanelSlot* CharacterButtonSlot = Root->AddChildToCanvas(CharacterButton))
	{
		CharacterButtonSlot->SetAnchors(FAnchors(1.0f, 1.0f));
		CharacterButtonSlot->SetAlignment(FVector2D(1.0f, 1.0f));
		CharacterButtonSlot->SetPosition(FVector2D(-16.0f, -16.0f));
		CharacterButtonSlot->SetSize(FVector2D(144.0f, 34.0f));
	}

	ModalBackdrop = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ModalBackdrop"));
	ModalBackdrop->SetBrushColor(UiBackdropColor);
	ModalBackdrop->SetVisibility(ESlateVisibility::Collapsed);
	if (UCanvasPanelSlot* BackdropSlot = Root->AddChildToCanvas(ModalBackdrop))
	{
		BackdropSlot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
		BackdropSlot->SetOffsets(FMargin(0.0f));
	}

	ModalPanel = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ModalPanel"));
	ModalPanel->SetBrushColor(UiPanelColor);
	ModalPanel->SetVisibility(ESlateVisibility::Collapsed);
	if (UCanvasPanelSlot* ModalSlot = Root->AddChildToCanvas(ModalPanel))
	{
		ModalSlot->SetAnchors(FAnchors(0.5f, 0.5f));
		ModalSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		ModalSlot->SetSize(FVector2D(620.0f, 520.0f));
	}

	RefreshFromSaveData();
	RebuildActionBars();
	RebuildModal();
}

void UFablePartyHudWidget::RebuildPartyMembers(const FFableCharacterProfile& ActiveProfile)
{
	if (PartyMembersBox == nullptr || WidgetTree == nullptr)
	{
		return;
	}

	PartyMembersBox->ClearChildren();
	PlayerHealthBar = nullptr;
	PlayerManaBar = nullptr;
	PlayerExperienceBar = nullptr;

	auto AddPartyCard = [&](const FString& Name, float HealthPct, float ManaPct, float ExperiencePct, bool bPlayerCard, const FString& PortraitLabel)
	{
		UBorder* Card = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
		Card->SetBrushColor(UiCardColor);
		Card->SetPadding(FMargin(8.0f));
		if (UVerticalBoxSlot* CardSlot = PartyMembersBox->AddChildToVerticalBox(Card))
		{
			CardSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 8.0f));
		}

		UHorizontalBox* CardRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass());
		Card->SetContent(CardRow);

		USizeBox* PortraitSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		PortraitSizeBox->SetWidthOverride(58.0f);
		PortraitSizeBox->SetHeightOverride(58.0f);
		if (UHorizontalBoxSlot* PortraitSlot = CardRow->AddChildToHorizontalBox(PortraitSizeBox))
		{
			PortraitSlot->SetPadding(FMargin(0.0f, 0.0f, 10.0f, 0.0f));
			PortraitSlot->SetVerticalAlignment(VAlign_Top);
		}

		UBorder* PortraitBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
		PortraitBorder->SetBrushColor(UiButtonColor);
		PortraitSizeBox->SetContent(PortraitBorder);

		UTextBlock* PortraitText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		PortraitText->SetText(FText::FromString(PortraitLabel));
		PortraitText->SetJustification(ETextJustify::Center);
		PortraitText->SetColorAndOpacity(FSlateColor(UiTextColor));
		PortraitBorder->SetContent(PortraitText);

		UVerticalBox* InfoColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass());
		if (UHorizontalBoxSlot* InfoSlot = CardRow->AddChildToHorizontalBox(InfoColumn))
		{
			FSlateChildSize FillSize;
			FillSize.SizeRule = ESlateSizeRule::Fill;
			FillSize.Value = 1.0f;
			InfoSlot->SetSize(FillSize);
		}

		UTextBlock* NameText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		NameText->SetText(FText::FromString(Name));
		NameText->SetColorAndOpacity(FSlateColor(UiTextColor));
		if (UVerticalBoxSlot* NameSlot = InfoColumn->AddChildToVerticalBox(NameText))
		{
			NameSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 6.0f));
		}

			auto AddStatBar = [&](float Percent, const FLinearColor& FillColor, TObjectPtr<UProgressBar>* OutPlayerBarRef)
			{
				UProgressBar* Bar = WidgetTree->ConstructWidget<UProgressBar>(UProgressBar::StaticClass());
				Bar->SetPercent(FMath::Clamp(Percent, 0.0f, 1.0f));
				Bar->SetFillColorAndOpacity(FillColor);
				USizeBox* BarSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
				BarSizeBox->SetHeightOverride(10.0f);
				BarSizeBox->SetContent(Bar);
				if (UVerticalBoxSlot* BarSlot = InfoColumn->AddChildToVerticalBox(BarSizeBox))
				{
					BarSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 6.0f));
				}

			if (OutPlayerBarRef != nullptr)
			{
				*OutPlayerBarRef = Bar;
			}
		};

			AddStatBar(HealthPct, UiHealthColor, bPlayerCard ? &PlayerHealthBar : nullptr);
			if (bPlayerCard)
			{
				AddStatBar(ManaPct, UiManaColor, &PlayerManaBar);
				AddStatBar(ExperiencePct, UiExperienceColor, &PlayerExperienceBar);
			}
	};

	const FString PlayerPortrait = ActiveProfile.CharacterName.IsEmpty()
		? TEXT("P")
		: ActiveProfile.CharacterName.Left(1).ToUpper();
	AddPartyCard(
		ActiveProfile.CharacterName.IsEmpty() ? TEXT("Adventurer") : ActiveProfile.CharacterName,
		ActiveProfile.HealthPercent,
		ActiveProfile.ManaPercent,
		ActiveProfile.ExperiencePercent,
		true,
		PlayerPortrait);

	for (const FString& CompanionName : ActiveProfile.CompanionNames)
	{
		const FString CompanionPortrait = CompanionName.IsEmpty() ? TEXT("C") : CompanionName.Left(1).ToUpper();
		AddPartyCard(CompanionName, 1.0f, 0.0f, 0.0f, false, CompanionPortrait);
	}
}

void UFablePartyHudWidget::RebuildActionBars()
{
	if (ActionBarsCanvas == nullptr || WidgetTree == nullptr)
	{
		return;
	}

	ActionBarsCanvas->ClearChildren();
	FVector2D ViewportSize = FVector2D(1920.0f, 1080.0f);
	if (GetWorld() != nullptr && GetWorld()->GetGameViewport() != nullptr)
	{
		GetWorld()->GetGameViewport()->GetViewportSize(ViewportSize);
	}

	for (FFableActionBarData& BarData : ActionBars)
	{
		const int32 VisibleRows = BarData.bExpanded ? BarData.ExpandedRows : BarData.Rows;
		const int32 VisibleCount = FMath::Max(1, VisibleRows) * FMath::Max(1, BarData.Columns);
		if (BarData.Slots.Num() < VisibleCount)
		{
			BarData.Slots.SetNum(VisibleCount);
		}

		TArray<FFableActionSlotData> VisibleSlots;
		VisibleSlots.SetNum(VisibleCount);
		for (int32 SlotIndex = 0; SlotIndex < VisibleCount; ++SlotIndex)
		{
			VisibleSlots[SlotIndex] = BarData.Slots.IsValidIndex(SlotIndex) ? BarData.Slots[SlotIndex] : FFableActionSlotData();
		}

		UFableActionBarWidget* BarWidget = WidgetTree->ConstructWidget<UFableActionBarWidget>(UFableActionBarWidget::StaticClass());
		BarWidget->InitializeBar(BarData, VisibleSlots, BarData.bIsMainBar, BarData.bExpanded);
		BarWidget->OnBarMoved.AddDynamic(this, &UFablePartyHudWidget::HandleActionBarMoved);
		BarWidget->OnExpandToggled.AddDynamic(this, &UFablePartyHudWidget::HandleActionBarExpandToggled);
		BarWidget->OnActionSlotDropped.AddDynamic(this, &UFablePartyHudWidget::HandleActionBarSlotDrop);
		BarWidget->OnRemoveRequested.AddDynamic(this, &UFablePartyHudWidget::HandleActionBarRemoveRequested);

		if (UCanvasPanelSlot* BarSlot = ActionBarsCanvas->AddChildToCanvas(BarWidget))
		{
			const int32 Columns = FMath::Max(1, BarData.Columns);
			const int32 Rows = FMath::Max(1, VisibleRows);
			const FVector2D Size = FVector2D(Columns * 62.0f + 84.0f, Rows * 62.0f + 16.0f);
			BarSlot->SetSize(Size);

			if (BarData.bIsMainBar)
			{
				BarSlot->SetAnchors(FAnchors(0.5f, 1.0f));
				BarSlot->SetAlignment(FVector2D(0.5f, 1.0f));
				const float BottomPadding = 16.0f;
				BarSlot->SetPosition(FVector2D(0.0f, -BottomPadding));
				BarData.ScreenPosition = FVector2D(0.0f, -BottomPadding);
			}
			else
			{
				BarSlot->SetAnchors(FAnchors(0.0f, 0.0f));
				BarSlot->SetAlignment(FVector2D(0.0f, 0.0f));

				FVector2D Position = BarData.ScreenPosition;
				Position.X = FMath::Clamp(Position.X, 0.0f, FMath::Max(0.0f, ViewportSize.X - Size.X));
				Position.Y = FMath::Clamp(Position.Y, 0.0f, FMath::Max(0.0f, ViewportSize.Y - Size.Y));
				BarData.ScreenPosition = Position;
				BarSlot->SetPosition(Position);
			}
		}
	}
}

bool UFablePartyHudWidget::IsValidActionPayload(const FString& PayloadId) const
{
	if (PayloadId.IsEmpty())
	{
		return false;
	}

	if (PayloadId.StartsWith(TEXT("skill:")))
	{
		return true;
	}

	if (const FString* TypeName = ItemTypeLookup.Find(PayloadId))
	{
		return *TypeName == TEXT("consumable");
	}

	return false;
}

bool UFablePartyHudWidget::ResolveActionSlotAddress(FName SlotId, FGuid& OutBarId, int32& OutSlotIndex) const
{
	OutBarId.Invalidate();
	OutSlotIndex = INDEX_NONE;

	const FString SlotString = SlotId.ToString();
	if (!SlotString.StartsWith(TEXT("action_")))
	{
		return false;
	}

	FString Tail = SlotString.RightChop(7);
	FString GuidToken;
	FString IndexToken;
	if (!Tail.Split(TEXT("_"), &GuidToken, &IndexToken, ESearchCase::CaseSensitive, ESearchDir::FromEnd))
	{
		return false;
	}

	if (!LexTryParseString(OutSlotIndex, *IndexToken))
	{
		return false;
	}

	return FGuid::ParseExact(GuidToken, EGuidFormats::Digits, OutBarId);
}

FString UFablePartyHudWidget::BuildActionToken(const FString& PayloadId) const
{
	if (PayloadId.IsEmpty())
	{
		return TEXT("");
	}

	FString Copy = PayloadId;
	Copy.ReplaceInline(TEXT("skill:"), TEXT(""));
	Copy.ReplaceInline(TEXT("_"), TEXT(" "));
	TArray<FString> Words;
	Copy.ParseIntoArray(Words, TEXT(" "), true);
	FString Token;
	for (const FString& Word : Words)
	{
		if (!Word.IsEmpty())
		{
			Token += Word.Left(1).ToUpper();
			if (Token.Len() >= 2)
			{
				break;
			}
		}
	}

	return Token.IsEmpty() ? Copy.Left(2).ToUpper() : Token;
}

void UFablePartyHudWidget::SaveActionBars()
{
	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		SaveSubsystem->SetActiveActionBars(ActionBars);
	}
}

void UFablePartyHudWidget::AddAdditionalActionBar(EFableActionBarOrientation Orientation)
{
	FFableActionBarData NewBar;
	NewBar.BarId = FGuid::NewGuid();
	NewBar.bIsMainBar = false;
	NewBar.Orientation = Orientation;
	NewBar.Columns = Orientation == EFableActionBarOrientation::Horizontal ? 10 : 1;
	NewBar.Rows = Orientation == EFableActionBarOrientation::Horizontal ? 1 : 10;
	NewBar.ExpandedRows = NewBar.Rows;
	NewBar.ScreenPosition = FVector2D(38.0f + ActionBars.Num() * 26.0f, 420.0f + ActionBars.Num() * 20.0f);
	NewBar.Slots.SetNum(NewBar.Columns * NewBar.Rows);
	ActionBars.Add(MoveTemp(NewBar));
	SaveActionBars();
	RebuildActionBars();
}

void UFablePartyHudWidget::RebuildModal()
{
	if (ModalPanel == nullptr || ModalBackdrop == nullptr || WidgetTree == nullptr)
	{
		return;
	}

	CharacterActionMap.Reset();
	SlotActionMap.Reset();

	if (UCanvasPanelSlot* ModalSlot = Cast<UCanvasPanelSlot>(ModalPanel->Slot))
	{
		if (ModalState == EModalState::ConfirmDeleteActionBar)
		{
			ModalSlot->SetSize(FVector2D(480.0f, 210.0f));
		}
		else
		{
			ModalSlot->SetSize(FVector2D(620.0f, 520.0f));
		}
	}

	if (ModalState == EModalState::None)
	{
		ModalBackdrop->SetVisibility(ESlateVisibility::Collapsed);
		ModalPanel->SetVisibility(ESlateVisibility::Collapsed);
		ModalPanel->SetContent(nullptr);
		return;
	}

	ModalBackdrop->SetVisibility(ESlateVisibility::Visible);
	ModalPanel->SetVisibility(ESlateVisibility::Visible);

	UVerticalBox* ModalBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ModalBox"));
	ModalPanel->SetContent(ModalBox);

	UHorizontalBox* HeaderRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("ModalHeaderRow"));
	if (UVerticalBoxSlot* HeaderSlot = ModalBox->AddChildToVerticalBox(HeaderRow))
	{
		HeaderSlot->SetPadding(FMargin(14.0f, 12.0f, 14.0f, 8.0f));
	}
	const bool bIsDeleteConfirmModal = ModalState == EModalState::ConfirmDeleteActionBar;

	USpacer* HeaderSpacerLeft = WidgetTree->ConstructWidget<USpacer>(USpacer::StaticClass());
	if (UHorizontalBoxSlot* SpacerSlot = HeaderRow->AddChildToHorizontalBox(HeaderSpacerLeft))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		SpacerSlot->SetSize(FillSize);
	}

	UTextBlock* TitleText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("ModalTitle"));
	TitleText->SetColorAndOpacity(FSlateColor(UiTextColor));
	TitleText->SetJustification(ETextJustify::Center);
	if (UHorizontalBoxSlot* TitleSlot = HeaderRow->AddChildToHorizontalBox(TitleText))
	{
		TitleSlot->SetPadding(FMargin(8.0f, 0.0f, 8.0f, 0.0f));
	}

	USpacer* HeaderSpacerRight = WidgetTree->ConstructWidget<USpacer>(USpacer::StaticClass());
	if (UHorizontalBoxSlot* SpacerSlot = HeaderRow->AddChildToHorizontalBox(HeaderSpacerRight))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		SpacerSlot->SetSize(FillSize);
	}

	if (!bIsDeleteConfirmModal)
	{
		UFableActionButton* CloseButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		CloseButton->InitializeAction(CloseModalAction);
		CloseButton->OnActionClicked.AddDynamic(this, &UFablePartyHudWidget::HandleActionClicked);
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
			CloseTextSlot->SetPadding(FMargin(9.0f, 4.0f));
		}
		if (UHorizontalBoxSlot* CloseSlot = HeaderRow->AddChildToHorizontalBox(CloseButton))
		{
			CloseSlot->SetHorizontalAlignment(HAlign_Right);
		}
	}

	UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (SaveSubsystem == nullptr)
	{
		TitleText->SetText(FText::FromString(TEXT("Save System Unavailable")));
		AddModalButton(ModalBox, TEXT("Close"), CloseModalAction);
		return;
	}

	if (ModalState == EModalState::SettingsRoot)
	{
		TitleText->SetText(FText::FromString(TEXT("Settings")));
		AddModalButton(ModalBox, TEXT("Save Game"), OpenSaveAction);
		AddModalButton(ModalBox, TEXT("Load Game"), OpenLoadAction);
		AddModalButton(ModalBox, TEXT("Add Horizontal Action Bar"), AddHorizontalActionBarAction);
		AddModalButton(ModalBox, TEXT("Add Vertical Action Bar"), AddVerticalActionBarAction);
		AddModalButton(ModalBox, TEXT("Quit to Main Menu"), QuitToMainMenuAction);
		return;
	}

	if (ModalState == EModalState::ConfirmDeleteActionBar)
	{
		TitleText->SetText(FText::FromString(TEXT("Remove Action Bar")));
		AddModalButton(ModalBox, TEXT("Delete"), ConfirmDeleteActionBarAction);
		AddModalButton(ModalBox, TEXT("Cancel"), CancelDeleteActionBarAction);
		return;
	}

	if (ModalState == EModalState::SaveSlots)
	{
		TitleText->SetText(FText::FromString(TEXT("Save Game")));

		FFableCharacterProfile Profile;
		if (!SaveSubsystem->TryGetActiveCharacterProfile(Profile))
		{
			AddModalButton(ModalBox, TEXT("No active character"), CloseModalAction, false);
			return;
		}

		TArray<FFableSaveSlotMeta> SaveSlots;
		SaveSubsystem->GetSaveSlots(Profile.CharacterId, SaveSlots);
		for (const FFableSaveSlotMeta& SlotMeta : SaveSlots)
		{
			AddModalButton(ModalBox, BuildSlotLabel(SlotMeta), RegisterSlotAction(SlotMeta.SlotIndex), true);
		}
		return;
	}

	if (ModalState == EModalState::LoadCharacters)
	{
		TitleText->SetText(FText::FromString(TEXT("Load Game: Character")));

		bool bAnyCharacters = false;
		for (const FFableCharacterProfile& Profile : SaveSubsystem->GetCharacters())
		{
			if (!SaveSubsystem->CharacterHasAnySavedSlots(Profile))
			{
				continue;
			}

			bAnyCharacters = true;
			AddModalButton(ModalBox, Profile.CharacterName, RegisterCharacterAction(Profile.CharacterId), true);
		}

		if (!bAnyCharacters)
		{
			AddModalButton(ModalBox, TEXT("No saved characters"), CloseModalAction, false);
		}
		return;
	}

	TitleText->SetText(FText::FromString(TEXT("Load Game: Slot")));
	TArray<FFableSaveSlotMeta> SaveSlots;
	SaveSubsystem->GetSaveSlots(PendingLoadCharacterId, SaveSlots);
	for (const FFableSaveSlotMeta& SlotMeta : SaveSlots)
	{
		if (!SlotMeta.bHasSave)
		{
			continue;
		}

		AddModalButton(ModalBox, BuildSlotLabel(SlotMeta), RegisterSlotAction(SlotMeta.SlotIndex), true);
	}
	AddModalButton(ModalBox, TEXT("Back"), OpenLoadAction, true);
}

void UFablePartyHudWidget::AddModalButton(UVerticalBox* Parent, const FString& Label, FName Action, bool bEnabled)
{
	if (Parent == nullptr || WidgetTree == nullptr)
	{
		return;
	}

	UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
	Button->InitializeAction(Action);
	Button->SetIsEnabled(bEnabled);
	Button->OnActionClicked.AddDynamic(this, &UFablePartyHudWidget::HandleActionClicked);
	Button->SetBackgroundColor(bEnabled ? UiButtonColor : UiButtonDisabledColor);

	UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Text->SetText(FText::FromString(Label));
	Text->SetColorAndOpacity(FSlateColor(UiTextColor));
	Text->SetJustification(ETextJustify::Center);
	Button->AddChild(Text);
	if (UButtonSlot* TextSlot = Cast<UButtonSlot>(Text->Slot))
	{
		TextSlot->SetHorizontalAlignment(HAlign_Center);
		TextSlot->SetVerticalAlignment(VAlign_Center);
		TextSlot->SetPadding(FMargin(10.0f, 10.0f));
	}

	if (UVerticalBoxSlot* Slot = Parent->AddChildToVerticalBox(Button))
	{
		Slot->SetPadding(FMargin(16.0f, 6.0f, 16.0f, 0.0f));
	}
}

FString UFablePartyHudWidget::BuildSlotLabel(const FFableSaveSlotMeta& SlotMeta) const
{
	if (!SlotMeta.bHasSave)
	{
		return FString::Printf(TEXT("Slot %d - Empty"), SlotMeta.SlotIndex + 1);
	}

	if (SlotMeta.LastPlayedUtc.IsEmpty())
	{
		return FString::Printf(TEXT("Slot %d - Saved"), SlotMeta.SlotIndex + 1);
	}

	return FString::Printf(TEXT("Slot %d - %s"), SlotMeta.SlotIndex + 1, *SlotMeta.LastPlayedUtc);
}

FName UFablePartyHudWidget::MakeActionName(const FString& Prefix)
{
	++ActionCounter;
	return FName(*FString::Printf(TEXT("%s_%d"), *Prefix, ActionCounter));
}

FName UFablePartyHudWidget::RegisterCharacterAction(const FGuid& CharacterId)
{
	const FName Action = MakeActionName(TEXT("character"));
	CharacterActionMap.Add(Action, CharacterId);
	return Action;
}

FName UFablePartyHudWidget::RegisterSlotAction(int32 SlotIndex)
{
	const FName Action = MakeActionName(TEXT("slot"));
	SlotActionMap.Add(Action, SlotIndex);
	return Action;
}

void UFablePartyHudWidget::HandleActionClicked(FName ActionId)
{
	if (ActionId == ToggleSettingsAction)
	{
		ModalState = ModalState == EModalState::None ? EModalState::SettingsRoot : EModalState::None;
		RebuildModal();
		return;
	}

	if (ActionId == OpenCharacterMenuAction)
	{
		if (CharacterMenuWidget != nullptr)
		{
			CharacterMenuWidget->Toggle();
		}
		return;
	}

	if (ActionId == OpenSaveAction)
	{
		ModalState = EModalState::SaveSlots;
		RebuildModal();
		return;
	}

	if (ActionId == OpenLoadAction)
	{
		ModalState = EModalState::LoadCharacters;
		RebuildModal();
		return;
	}

	if (ActionId == AddHorizontalActionBarAction)
	{
		AddAdditionalActionBar(EFableActionBarOrientation::Horizontal);
		return;
	}

	if (ActionId == AddVerticalActionBarAction)
	{
		AddAdditionalActionBar(EFableActionBarOrientation::Vertical);
		return;
	}

	if (ActionId == QuitToMainMenuAction)
	{
		if (CharacterMenuWidget != nullptr && CharacterMenuWidget->IsOpen())
		{
			CharacterMenuWidget->Close();
		}

		if (AFableForgePlayerController* Controller = Cast<AFableForgePlayerController>(GetOwningPlayer()))
		{
			ModalState = EModalState::None;
			RebuildModal();
			Controller->ShowMainMenu();
		}
		return;
	}

	if (ActionId == CloseModalAction)
	{
		ModalState = EModalState::None;
		RebuildModal();
		return;
	}

	if (ActionId == CancelDeleteActionBarAction)
	{
		PendingDeleteActionBarId.Invalidate();
		ModalState = EModalState::None;
		RebuildModal();
		return;
	}

	if (ActionId == ConfirmDeleteActionBarAction)
	{
		if (PendingDeleteActionBarId.IsValid())
		{
			const int32 RemovedCount = ActionBars.RemoveAll(
				[this](const FFableActionBarData& BarData)
				{
					return !BarData.bIsMainBar && BarData.BarId == PendingDeleteActionBarId;
				});
			if (RemovedCount > 0)
			{
				SaveActionBars();
				RebuildActionBars();
			}
		}

		PendingDeleteActionBarId.Invalidate();
		ModalState = EModalState::None;
		RebuildModal();
		return;
	}

	if (const FGuid* CharacterId = CharacterActionMap.Find(ActionId))
	{
		PendingLoadCharacterId = *CharacterId;
		ModalState = EModalState::LoadSlots;
		RebuildModal();
		return;
	}

	if (const int32* SlotIndex = SlotActionMap.Find(ActionId))
	{
		UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
		if (SaveSubsystem == nullptr)
		{
			return;
		}

		if (ModalState == EModalState::SaveSlots)
		{
			const FGuid ActiveCharacterId = SaveSubsystem->GetActiveCharacterId();
			if (ActiveCharacterId.IsValid())
			{
				const FString MapName = GetWorld() ? GetWorld()->GetMapName() : TEXT("");
				SaveSubsystem->SaveCharacterToSlot(ActiveCharacterId, *SlotIndex, MapName);
				RefreshFromSaveData();
			}
			ModalState = EModalState::None;
			RebuildModal();
			return;
		}

		if (ModalState == EModalState::LoadSlots)
		{
			if (AFableForgePlayerController* Controller = Cast<AFableForgePlayerController>(GetOwningPlayer()))
			{
				Controller->EnterGameFromCharacterSlot(PendingLoadCharacterId, *SlotIndex, false);
			}

			ModalState = EModalState::None;
			RebuildModal();
		}
	}
}

void UFablePartyHudWidget::HandleActionBarMoved(FGuid BarId, FVector2D NewScreenPosition)
{
	FVector2D ViewportSize = FVector2D(1920.0f, 1080.0f);
	if (GetWorld() != nullptr && GetWorld()->GetGameViewport() != nullptr)
	{
		GetWorld()->GetGameViewport()->GetViewportSize(ViewportSize);
	}

	for (FFableActionBarData& BarData : ActionBars)
	{
		if (BarData.BarId == BarId)
		{
			if (BarData.bIsMainBar)
			{
				return;
			}

			const int32 VisibleRows = BarData.bExpanded ? BarData.ExpandedRows : BarData.Rows;
			const FVector2D Size(
				FMath::Max(1, BarData.Columns) * 62.0f + 84.0f,
				FMath::Max(1, VisibleRows) * 62.0f + 16.0f);
			NewScreenPosition.X = FMath::Clamp(NewScreenPosition.X, 0.0f, FMath::Max(0.0f, ViewportSize.X - Size.X));
			NewScreenPosition.Y = FMath::Clamp(NewScreenPosition.Y, 0.0f, FMath::Max(0.0f, ViewportSize.Y - Size.Y));
			BarData.ScreenPosition = NewScreenPosition;
			SaveActionBars();
			return;
		}
	}
}

void UFablePartyHudWidget::HandleActionBarExpandToggled(FGuid BarId)
{
	for (FFableActionBarData& BarData : ActionBars)
	{
		if (BarData.BarId == BarId && BarData.bIsMainBar)
		{
			BarData.bExpanded = !BarData.bExpanded;
			SaveActionBars();
			RebuildActionBars();
			return;
		}
	}
}

void UFablePartyHudWidget::HandleActionBarSlotDrop(FGuid BarId, int32 ToSlotIndex, FName FromSlotId, const FString& PayloadId, const FString& PayloadLabel)
{
	FFableActionBarData* TargetBar = ActionBars.FindByPredicate([&BarId](const FFableActionBarData& Bar) { return Bar.BarId == BarId; });
	if (TargetBar == nullptr || !TargetBar->Slots.IsValidIndex(ToSlotIndex))
	{
		return;
	}

	FGuid SourceBarId;
	int32 SourceSlotIndex = INDEX_NONE;
	if (ResolveActionSlotAddress(FromSlotId, SourceBarId, SourceSlotIndex))
	{
		FFableActionBarData* SourceBar = ActionBars.FindByPredicate([&SourceBarId](const FFableActionBarData& Bar) { return Bar.BarId == SourceBarId; });
		if (SourceBar != nullptr && SourceBar->Slots.IsValidIndex(SourceSlotIndex))
		{
			const FFableActionSlotData Temp = SourceBar->Slots[SourceSlotIndex];
			SourceBar->Slots[SourceSlotIndex] = TargetBar->Slots[ToSlotIndex];
			TargetBar->Slots[ToSlotIndex] = Temp;
			SaveActionBars();
			RebuildActionBars();
		}
		return;
	}

	if (!IsValidActionPayload(PayloadId))
	{
		return;
	}

	TargetBar->Slots[ToSlotIndex].EntryId = PayloadId;
	TargetBar->Slots[ToSlotIndex].EntryLabel = PayloadLabel.IsEmpty() ? BuildActionToken(PayloadId) : PayloadLabel;
	SaveActionBars();
	RebuildActionBars();
}

void UFablePartyHudWidget::HandleActionBarRemoveRequested(FGuid BarId)
{
	const FFableActionBarData* BarData = ActionBars.FindByPredicate([&BarId](const FFableActionBarData& Candidate)
	{
		return Candidate.BarId == BarId;
	});
	if (BarData == nullptr || BarData->bIsMainBar)
	{
		return;
	}

	PendingDeleteActionBarId = BarId;
	ModalState = EModalState::ConfirmDeleteActionBar;
	RebuildModal();
}
