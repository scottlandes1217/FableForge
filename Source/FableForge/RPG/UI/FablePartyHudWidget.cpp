#include "RPG/UI/FablePartyHudWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/ButtonSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/Image.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
#include "Components/ProgressBar.h"
#include "Components/SizeBox.h"
#include "Components/Spacer.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Engine/GameViewportClient.h"
#include "Engine/DataTable.h"
#include "Engine/SceneCapture2D.h"
#include "Engine/TextureRenderTarget2D.h"
#include "FableForgePlayerController.h"
#include "Misc/FileHelper.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "RPG/UI/FableActionButton.h"
#include "RPG/UI/FableActionBarWidget.h"
#include "RPG/UI/FableCharacterMenuWidget.h"
#include "FableForgePlayerController.h"
#include "FableForge.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Components/PrimitiveComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/SceneCaptureComponent2D.h"
#include "GameFramework/Character.h"
#include "Kismet/KismetMathLibrary.h"

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
	const TCHAR* SkillsDataTablePath = TEXT("/Game/Data/DT_Skills.DT_Skills");

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

void UFablePartyHudWidget::NativeDestruct()
{
	if (PlayerPortraitCaptureActor != nullptr)
	{
		PlayerPortraitCaptureActor->Destroy();
		PlayerPortraitCaptureActor = nullptr;
	}

	PlayerPortraitRenderTarget = nullptr;
	Super::NativeDestruct();
}

void UFablePartyHudWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);

	if (ActionCooldownsByPayload.Num() == 0)
	{
		return;
	}

	bool bCooldownsChanged = false;
	TArray<FString> ExpiredPayloads;
	for (TPair<FString, float>& Pair : ActionCooldownsByPayload)
	{
		Pair.Value = FMath::Max(0.0f, Pair.Value - InDeltaTime);
		if (Pair.Value <= KINDA_SMALL_NUMBER)
		{
			ExpiredPayloads.Add(Pair.Key);
		}
		bCooldownsChanged = true;
	}

	for (const FString& PayloadId : ExpiredPayloads)
	{
		ActionCooldownsByPayload.Remove(PayloadId);
	}

	if (bCooldownsChanged)
	{
		UpdateActionBarCooldownVisuals();
	}
}

void UFablePartyHudWidget::SetCharacterMenuWidget(UFableCharacterMenuWidget* InCharacterMenuWidget)
{
	CharacterMenuWidget = InCharacterMenuWidget;
}

bool UFablePartyHudWidget::TryAssignActionAtScreenPosition(const FVector2D& ScreenPosition, FName FromSlotId, const FString& PayloadId, const FString& PayloadLabel)
{
	if (ActionBarsCanvas == nullptr)
	{
		return false;
	}

	const int32 ChildCount = ActionBarsCanvas->GetChildrenCount();
	for (int32 ChildIndex = ChildCount - 1; ChildIndex >= 0; --ChildIndex)
	{
		UWidget* ChildWidget = ActionBarsCanvas->GetChildAt(ChildIndex);
		UFableActionBarWidget* ActionBarWidget = Cast<UFableActionBarWidget>(ChildWidget);
		if (ActionBarWidget == nullptr)
		{
			continue;
		}

		int32 ToSlotIndex = INDEX_NONE;
		if (!ActionBarWidget->TryResolveSlotIndexFromScreenPosition(ScreenPosition, ToSlotIndex))
		{
			continue;
		}

		UE_LOG(LogFableForge, Log, TEXT("ActionBar manual drop bar=%s slotIndex=%d from=%s payload=%s label=%s"),
			*ActionBarWidget->GetBarId().ToString(EGuidFormats::Digits),
			ToSlotIndex,
			*FromSlotId.ToString(),
			*PayloadId,
			*PayloadLabel);
		HandleActionBarSlotDrop(ActionBarWidget->GetBarId(), ToSlotIndex, FromSlotId, PayloadId, PayloadLabel);
		return true;
	}

	return false;
}

bool UFablePartyHudWidget::TryUseActionAtScreenPosition(const FVector2D& ScreenPosition)
{
	if (ActionBarsCanvas == nullptr)
	{
		UE_LOG(LogFableForge, Verbose, TEXT("ActionBar use hit-test skipped: ActionBarsCanvas missing"));
		return false;
	}

	const int32 ChildCount = ActionBarsCanvas->GetChildrenCount();
	for (int32 ChildIndex = ChildCount - 1; ChildIndex >= 0; --ChildIndex)
	{
		UWidget* ChildWidget = ActionBarsCanvas->GetChildAt(ChildIndex);
		UFableActionBarWidget* ActionBarWidget = Cast<UFableActionBarWidget>(ChildWidget);
		if (ActionBarWidget == nullptr || !ActionBarWidget->IsVisible())
		{
			continue;
		}

		int32 SlotIndex = INDEX_NONE;
		if (!ActionBarWidget->TryResolveSlotIndexFromScreenPosition(ScreenPosition, SlotIndex))
		{
			continue;
		}

		const FGuid BarId = ActionBarWidget->GetBarId();
		const FFableActionBarData* BarData = ActionBars.FindByPredicate([&BarId](const FFableActionBarData& Candidate)
		{
			return Candidate.BarId == BarId;
		});

		const FString PayloadId = (BarData != nullptr && BarData->Slots.IsValidIndex(SlotIndex))
			? BarData->Slots[SlotIndex].EntryId
			: FString();

		UE_LOG(LogFableForge, Log, TEXT("ActionBar controller hit-test bar=%s slot=%d payload=%s"),
			*BarId.ToString(EGuidFormats::Digits), SlotIndex, *PayloadId);

		if (PayloadId.IsEmpty())
		{
			return true; // Cursor is over an action slot; block world click even if empty.
		}

		HandleActionBarSlotClicked(BarId, SlotIndex, PayloadId);
		return true;
	}

	return false;
}

bool UFablePartyHudWidget::ClearActionAtSlotId(FName SlotId)
{
	FGuid BarId;
	int32 SlotIndex = INDEX_NONE;
	if (!ResolveActionSlotAddress(SlotId, BarId, SlotIndex))
	{
		return false;
	}

	FFableActionBarData* Bar = ActionBars.FindByPredicate([&BarId](const FFableActionBarData& Candidate)
	{
		return Candidate.BarId == BarId;
	});
	if (Bar == nullptr || !Bar->Slots.IsValidIndex(SlotIndex))
	{
		return false;
	}

	Bar->Slots[SlotIndex] = FFableActionSlotData();
	UE_LOG(LogFableForge, Log, TEXT("ActionBar clear slot bar=%s slotIndex=%d"),
		*BarId.ToString(EGuidFormats::Digits), SlotIndex);
	SaveActionBars();
	RebuildActionBars();
	return true;
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
	UpdatePlayerPortraitCapture();
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
	Root->SetVisibility(ESlateVisibility::Visible);
	WidgetTree->RootWidget = Root;

	ActionBarsCanvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("ActionBarsCanvas"));
	ActionBarsCanvas->SetVisibility(ESlateVisibility::Visible);
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
	PlayerPortraitImage = nullptr;
	PlayerPortraitFallbackText = nullptr;

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
		PortraitSizeBox->SetWidthOverride(64.0f);
		PortraitSizeBox->SetHeightOverride(74.0f);
		if (UHorizontalBoxSlot* PortraitSlot = CardRow->AddChildToHorizontalBox(PortraitSizeBox))
		{
			PortraitSlot->SetPadding(FMargin(0.0f, 0.0f, 10.0f, 0.0f));
			PortraitSlot->SetVerticalAlignment(VAlign_Top);
		}

		UBorder* PortraitBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
		PortraitBorder->SetBrushColor(UiButtonColor);
		PortraitSizeBox->SetContent(PortraitBorder);

		UOverlay* PortraitOverlay = WidgetTree->ConstructWidget<UOverlay>(UOverlay::StaticClass());
		PortraitBorder->SetContent(PortraitOverlay);

		UImage* PortraitImage = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass());
		if (UOverlaySlot* PortraitImageSlot = PortraitOverlay->AddChildToOverlay(PortraitImage))
		{
			PortraitImageSlot->SetHorizontalAlignment(HAlign_Fill);
			PortraitImageSlot->SetVerticalAlignment(VAlign_Fill);
		}

		UTextBlock* PortraitText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		PortraitText->SetText(FText::FromString(PortraitLabel));
		PortraitText->SetJustification(ETextJustify::Center);
		PortraitText->SetColorAndOpacity(FSlateColor(UiTextColor));
		if (UOverlaySlot* PortraitTextSlot = PortraitOverlay->AddChildToOverlay(PortraitText))
		{
			PortraitTextSlot->SetHorizontalAlignment(HAlign_Center);
			PortraitTextSlot->SetVerticalAlignment(VAlign_Center);
		}

		if (bPlayerCard)
		{
			PlayerPortraitImage = PortraitImage;
			PlayerPortraitFallbackText = PortraitText;
		}

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

	UpdatePlayerPortraitCapture();
}

void UFablePartyHudWidget::EnsurePlayerPortraitCapture()
{
	if (PlayerPortraitRenderTarget == nullptr)
	{
		PlayerPortraitRenderTarget = NewObject<UTextureRenderTarget2D>(this, TEXT("PlayerPortraitRT"));
		if (PlayerPortraitRenderTarget != nullptr)
		{
			PlayerPortraitRenderTarget->RenderTargetFormat = ETextureRenderTargetFormat::RTF_RGBA8;
			PlayerPortraitRenderTarget->ClearColor = FLinearColor(0.03f, 0.03f, 0.03f, 1.0f);
			PlayerPortraitRenderTarget->InitAutoFormat(256, 256);
			PlayerPortraitRenderTarget->UpdateResourceImmediate(true);
		}
	}

	if (PlayerPortraitCaptureActor == nullptr)
	{
		UWorld* World = GetWorld();
		if (World == nullptr)
		{
			return;
		}

		PlayerPortraitCaptureActor = World->SpawnActor<ASceneCapture2D>(ASceneCapture2D::StaticClass(), FTransform::Identity);
		if (PlayerPortraitCaptureActor != nullptr)
		{
			PlayerPortraitCaptureActor->SetActorHiddenInGame(false);
			PlayerPortraitCaptureActor->SetActorEnableCollision(false);
			if (USceneCaptureComponent2D* Capture = PlayerPortraitCaptureActor->GetCaptureComponent2D())
			{
				Capture->bCaptureEveryFrame = false;
				Capture->bCaptureOnMovement = false;
				Capture->TextureTarget = PlayerPortraitRenderTarget;
				Capture->CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR;
				Capture->FOVAngle = 22.0f;
				Capture->PrimitiveRenderMode = ESceneCapturePrimitiveRenderMode::PRM_UseShowOnlyList;
				Capture->ShowOnlyActors.Empty();
				Capture->ShowOnlyComponents.Empty();
				Capture->PostProcessBlendWeight = 1.0f;
				Capture->PostProcessSettings.bOverride_AutoExposureBias = true;
				Capture->PostProcessSettings.AutoExposureBias = 6.0f;
			}
		}
	}

	if (PlayerPortraitImage != nullptr && PlayerPortraitRenderTarget != nullptr)
	{
		FSlateBrush Brush = PlayerPortraitImage->GetBrush();
		Brush.SetResourceObject(PlayerPortraitRenderTarget);
		Brush.ImageSize = FVector2D(64.0f, 74.0f);
		PlayerPortraitImage->SetBrush(Brush);
		PlayerPortraitImage->SetColorAndOpacity(FLinearColor::White);
	}
}

void UFablePartyHudWidget::UpdatePlayerPortraitCapture()
{
	if (PlayerPortraitImage == nullptr)
	{
		return;
	}

	EnsurePlayerPortraitCapture();
	if (PlayerPortraitCaptureActor == nullptr || PlayerPortraitRenderTarget == nullptr)
	{
		if (PlayerPortraitFallbackText != nullptr)
		{
			PlayerPortraitFallbackText->SetVisibility(ESlateVisibility::Visible);
		}
		PlayerPortraitImage->SetVisibility(ESlateVisibility::Collapsed);
		return;
	}

	APawn* PlayerPawn = GetOwningPlayerPawn();
	if (PlayerPawn == nullptr)
	{
		if (PlayerPortraitFallbackText != nullptr)
		{
			PlayerPortraitFallbackText->SetVisibility(ESlateVisibility::Visible);
		}
		PlayerPortraitImage->SetVisibility(ESlateVisibility::Collapsed);
		return;
	}

	USceneCaptureComponent2D* Capture = PlayerPortraitCaptureActor->GetCaptureComponent2D();
	if (Capture == nullptr)
	{
		return;
	}

	Capture->TextureTarget = PlayerPortraitRenderTarget;
	Capture->PrimitiveRenderMode = ESceneCapturePrimitiveRenderMode::PRM_UseShowOnlyList;
	Capture->ShowOnlyActors.Empty();
	Capture->ClearShowOnlyComponents();
	Capture->ShowOnlyActorComponents(PlayerPawn, true);

	int32 RemovedCapsules = 0;
	TArray<UPrimitiveComponent*> PortraitComponents;
	PlayerPawn->GetComponents<UPrimitiveComponent>(PortraitComponents);
	for (UPrimitiveComponent* Primitive : PortraitComponents)
	{
		if (Primitive != nullptr && Primitive->IsA<UCapsuleComponent>())
		{
			Capture->RemoveShowOnlyComponent(Primitive);
			++RemovedCapsules;
		}
	}

	const int32 AddedPortraitComponents = Capture->ShowOnlyComponents.Num();
	if (AddedPortraitComponents <= 0)
	{
		if (PlayerPortraitFallbackText != nullptr)
		{
			PlayerPortraitFallbackText->SetVisibility(ESlateVisibility::Visible);
		}
		PlayerPortraitImage->SetVisibility(ESlateVisibility::Collapsed);
		UE_LOG(LogFableForge, Warning, TEXT("Portrait capture: no visible primitive components found on pawn %s"), *GetNameSafe(PlayerPawn));
		return;
	}
	UE_LOG(LogFableForge, Log, TEXT("Portrait capture components=%d (capsules removed=%d) pawn=%s"),
		AddedPortraitComponents, RemovedCapsules, *GetNameSafe(PlayerPawn));

	FVector BoundsOrigin = PlayerPawn->GetActorLocation();
	FVector BoundsExtent(30.0f, 30.0f, 88.0f);
	FVector PortraitForward = PlayerPawn->GetActorForwardVector();
	FVector PortraitRight = PlayerPawn->GetActorRightVector();
	if (ACharacter* CharacterPawn = Cast<ACharacter>(PlayerPawn))
	{
		if (USkeletalMeshComponent* MeshComp = CharacterPawn->GetMesh())
		{
			BoundsOrigin = MeshComp->Bounds.Origin;
			BoundsExtent = MeshComp->Bounds.BoxExtent;
			PortraitForward = MeshComp->GetForwardVector();
			PortraitRight = MeshComp->GetRightVector();
		}
		else
		{
			PlayerPawn->GetActorBounds(true, BoundsOrigin, BoundsExtent);
		}
	}
	else
	{
		PlayerPawn->GetActorBounds(true, BoundsOrigin, BoundsExtent);
	}

	const FVector FocusPoint = BoundsOrigin + FVector(0.0f, 0.0f, BoundsExtent.Z * 0.82f);
	const float CameraDistance = FMath::Clamp(BoundsExtent.Z * 1.55f, 110.0f, 240.0f);
	const FVector PortraitDirection = (PortraitRight).GetSafeNormal();
	const FVector CaptureLocation = FocusPoint + (PortraitDirection * CameraDistance) + FVector(0.0f, 0.0f, BoundsExtent.Z * 0.02f);
	PlayerPortraitCaptureActor->SetActorLocation(CaptureLocation);
	PlayerPortraitCaptureActor->SetActorRotation(UKismetMathLibrary::FindLookAtRotation(CaptureLocation, FocusPoint));
	Capture->CaptureScene();

	PlayerPortraitImage->SetVisibility(ESlateVisibility::HitTestInvisible);
	if (PlayerPortraitFallbackText != nullptr)
	{
		PlayerPortraitFallbackText->SetVisibility(ESlateVisibility::Collapsed);
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
		BarWidget->SetVisibility(ESlateVisibility::Visible);
		BarWidget->SetIsEnabled(true);
		BarWidget->InitializeBar(BarData, VisibleSlots, BarData.bIsMainBar, BarData.bExpanded);
		BarWidget->OnBarMoved.AddDynamic(this, &UFablePartyHudWidget::HandleActionBarMoved);
		BarWidget->OnExpandToggled.AddDynamic(this, &UFablePartyHudWidget::HandleActionBarExpandToggled);
		BarWidget->OnActionSlotDropped.AddDynamic(this, &UFablePartyHudWidget::HandleActionBarSlotDrop);
		BarWidget->OnActionSlotClicked.AddDynamic(this, &UFablePartyHudWidget::HandleActionBarSlotClicked);
		BarWidget->OnRemoveRequested.AddDynamic(this, &UFablePartyHudWidget::HandleActionBarRemoveRequested);

		for (int32 SlotIndex = 0; SlotIndex < VisibleSlots.Num(); ++SlotIndex)
		{
			const FFableActionSlotData& SlotData = VisibleSlots[SlotIndex];
			const float* CooldownRemaining = ActionCooldownsByPayload.Find(SlotData.EntryId);
			BarWidget->SetSlotCooldownRemaining(SlotIndex, CooldownRemaining != nullptr ? *CooldownRemaining : 0.0f);
		}

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
		if (AFableForgePlayerController* Controller = Cast<AFableForgePlayerController>(GetOwningPlayer()))
		{
			Controller->ToggleCharacterMenu();
		}
		else if (CharacterMenuWidget != nullptr)
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

void UFablePartyHudWidget::HandleActionBarSlotClicked(FGuid BarId, int32 SlotIndex, const FString& PayloadId)
{
	UE_LOG(LogFableForge, Log, TEXT("ActionBar use requested bar=%s slot=%d payload=%s"),
		*BarId.ToString(EGuidFormats::Digits), SlotIndex, *PayloadId);

	if (PayloadId.IsEmpty())
	{
		UE_LOG(LogFableForge, Warning, TEXT("ActionBar use ignored: empty payload bar=%s slot=%d"),
			*BarId.ToString(EGuidFormats::Digits), SlotIndex);
		return;
	}

	if (const float* ExistingCooldown = ActionCooldownsByPayload.Find(PayloadId))
	{
		if (*ExistingCooldown > KINDA_SMALL_NUMBER)
		{
			UE_LOG(LogFableForge, Log, TEXT("ActionBar use blocked by cooldown bar=%s slot=%d payload=%s remaining=%.2f"),
				*BarId.ToString(EGuidFormats::Digits), SlotIndex, *PayloadId, *ExistingCooldown);
			return;
		}
	}

	if (UFableActionBarWidget* BarWidget = FindActionBarWidgetById(BarId))
	{
		BarWidget->PlaySlotUseFeedback(SlotIndex);
	}
	else
	{
		UE_LOG(LogFableForge, Warning, TEXT("ActionBar use feedback failed: bar widget not found bar=%s slot=%d payload=%s"),
			*BarId.ToString(EGuidFormats::Digits), SlotIndex, *PayloadId);
	}

	float CooldownSeconds = 0.0f;

	if (PayloadId.StartsWith(TEXT("skill:")))
	{
		FString SkillId = PayloadId;
		SkillId.RemoveFromStart(TEXT("skill:"));

		LoadSkillDefinitionsFromDataTable();
		if (const FFableSkillDefinitionTableRow* SkillRow = FindSkillDefinition(SkillId))
		{
			CooldownSeconds = FMath::Max(0.0f, SkillRow->CooldownSeconds);
			UE_LOG(LogFableForge, Log, TEXT("ActionBar skill resolved skillId=%s cooldown=%.2f cast=%.2f"),
				*SkillId, CooldownSeconds, SkillRow->CastTimeSeconds);

			if (ACharacter* CharacterPawn = Cast<ACharacter>(GetOwningPlayerPawn()))
			{
				if (USkeletalMeshComponent* MeshComp = CharacterPawn->GetMesh())
				{
					if (UAnimationAsset* AnimAsset = SkillRow->CharacterAnimationAsset.LoadSynchronous())
					{
						UE_LOG(LogFableForge, Log, TEXT("ActionBar playing character animation skillId=%s anim=%s"),
							*SkillId, *GetNameSafe(AnimAsset));
						MeshComp->PlayAnimation(AnimAsset, false);
					}
					else
					{
						UE_LOG(LogFableForge, Log, TEXT("ActionBar no character animation asset for skillId=%s"), *SkillId);
					}
				}
				else
				{
					UE_LOG(LogFableForge, Warning, TEXT("ActionBar skill use: character mesh missing for skillId=%s"), *SkillId);
				}
			}
			else
			{
				UE_LOG(LogFableForge, Warning, TEXT("ActionBar skill use: owning pawn is not ACharacter for skillId=%s pawn=%s"),
					*SkillId, *GetNameSafe(GetOwningPlayerPawn()));
			}
		}
		else
		{
			UE_LOG(LogFableForge, Warning, TEXT("ActionBar skill click missing skill definition skillId=%s"), *SkillId);
		}
	}

	if (CooldownSeconds > 0.0f)
	{
		ActionCooldownsByPayload.Add(PayloadId, CooldownSeconds);
		UE_LOG(LogFableForge, Log, TEXT("ActionBar cooldown started payload=%s seconds=%.2f"), *PayloadId, CooldownSeconds);
		UpdateActionBarCooldownVisuals();
	}
	else
	{
		UE_LOG(LogFableForge, Log, TEXT("ActionBar use completed without cooldown payload=%s"), *PayloadId);
	}
}

void UFablePartyHudWidget::LoadSkillDefinitionsFromDataTable()
{
	if (bSkillDefinitionsLoaded)
	{
		return;
	}

	SkillDefinitions.Reset();
	if (UDataTable* SkillsTable = LoadObject<UDataTable>(nullptr, SkillsDataTablePath))
	{
		static const FString ContextString(TEXT("UFablePartyHudWidget::LoadSkillDefinitionsFromDataTable"));
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

const FFableSkillDefinitionTableRow* UFablePartyHudWidget::FindSkillDefinition(const FString& SkillId) const
{
	return SkillDefinitions.Find(SkillId);
}

void UFablePartyHudWidget::UpdateActionBarCooldownVisuals()
{
	if (ActionBarsCanvas == nullptr)
	{
		return;
	}

	for (int32 ChildIndex = 0; ChildIndex < ActionBarsCanvas->GetChildrenCount(); ++ChildIndex)
	{
		UFableActionBarWidget* BarWidget = Cast<UFableActionBarWidget>(ActionBarsCanvas->GetChildAt(ChildIndex));
		if (BarWidget == nullptr)
		{
			continue;
		}

		const FFableActionBarData* BarData = ActionBars.FindByPredicate([&BarWidget](const FFableActionBarData& Candidate)
		{
			return Candidate.BarId == BarWidget->GetBarId();
		});
		if (BarData == nullptr)
		{
			continue;
		}

		const int32 VisibleRows = BarData->bExpanded ? BarData->ExpandedRows : BarData->Rows;
		const int32 VisibleCount = FMath::Max(1, VisibleRows) * FMath::Max(1, BarData->Columns);
		for (int32 SlotIndex = 0; SlotIndex < VisibleCount; ++SlotIndex)
		{
			const FString PayloadId = BarData->Slots.IsValidIndex(SlotIndex) ? BarData->Slots[SlotIndex].EntryId : FString();
			const float* CooldownRemaining = ActionCooldownsByPayload.Find(PayloadId);
			BarWidget->SetSlotCooldownRemaining(SlotIndex, CooldownRemaining != nullptr ? *CooldownRemaining : 0.0f);
		}
	}
}

UFableActionBarWidget* UFablePartyHudWidget::FindActionBarWidgetById(const FGuid& BarId) const
{
	if (ActionBarsCanvas == nullptr)
	{
		return nullptr;
	}

	for (int32 ChildIndex = 0; ChildIndex < ActionBarsCanvas->GetChildrenCount(); ++ChildIndex)
	{
		UFableActionBarWidget* BarWidget = Cast<UFableActionBarWidget>(ActionBarsCanvas->GetChildAt(ChildIndex));
		if (BarWidget != nullptr && BarWidget->GetBarId() == BarId)
		{
			return BarWidget;
		}
	}

	return nullptr;
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
