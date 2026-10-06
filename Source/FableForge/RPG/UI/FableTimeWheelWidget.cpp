#include "RPG/UI/FableTimeWheelWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Blueprint/WidgetLayoutLibrary.h"
#include "Rendering/DrawElements.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/Border.h"
#include "Components/Image.h"
#include "Components/TextBlock.h"
#include "RPG/Data/FableSkillSystemTableRows.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "RPG/UI/FableItemIconLibrary.h"
#include "Engine/DataTable.h"
#include "Brushes/SlateRoundedBoxBrush.h"
#include "Engine/Texture2D.h"
#include "UObject/StrongObjectPtr.h"
#include "ImageUtils.h"
#include "ImageCore.h"
#include "Misc/Paths.h"
#include "RPG/UI/FableBookStyle.h"
#include "Styling/SlateTypes.h"
#include "Styling/SlateColor.h"

namespace
{
	constexpr float QuickWheelStickDeadzone = 0.24f;
	// Keep the current slot until the stick has moved well into the next
	// sector. This prevents axis noise at an octant boundary from oscillating
	// the selection while preserving the existing eight-slot layout.
	constexpr float QuickWheelSelectionHysteresisDot = 0.8660254f; // cos(30 degrees)

	FString ToDisplayName(const FString& RawName)
	{
		if (RawName.IsEmpty()) return TEXT("Empty slot");
		FString Result = RawName;
		Result.ReplaceInline(TEXT("skill:"), TEXT(""), ESearchCase::IgnoreCase);
		Result.ReplaceInline(TEXT("item:"), TEXT(""), ESearchCase::IgnoreCase);
		Result.ReplaceInline(TEXT("_"), TEXT(" "));
		Result.TrimStartAndEndInline();
		bool bCapitalize = true;
		for (TCHAR& Character : Result)
		{
			if (bCapitalize && FChar::IsAlpha(Character))
			{
				Character = FChar::ToUpper(Character);
				bCapitalize = false;
			}
			else if (Character == TEXT(' '))
			{
				bCapitalize = true;
			}
		}
		return Result;
	}

	FLinearColor ElementColor(const FName& Element)
	{
		const FString Name = Element.ToString();
		if (Name.Equals(TEXT("Fire"), ESearchCase::IgnoreCase)) return FLinearColor(0.95f, 0.28f, 0.08f, 1.0f);
		if (Name.Equals(TEXT("Water"), ESearchCase::IgnoreCase)) return FLinearColor(0.12f, 0.52f, 0.95f, 1.0f);
		if (Name.Equals(TEXT("Air"), ESearchCase::IgnoreCase)) return FLinearColor(0.45f, 0.84f, 0.95f, 1.0f);
		if (Name.Equals(TEXT("Earth"), ESearchCase::IgnoreCase)) return FLinearColor(0.65f, 0.42f, 0.18f, 1.0f);
		return FLinearColor(0.78f, 0.62f, 0.26f, 1.0f);
	}

	FString GestureDisplayName(const FString& Gesture)
	{
		return Gesture.IsEmpty() || Gesture.Equals(TEXT("Ready"), ESearchCase::IgnoreCase)
			? TEXT("Ready to shape") : ToDisplayName(Gesture);
	}

	const FFableSkillDefinitionTableRow* FindWheelSkillDefinition(const FString& SkillId, FFableSkillDefinitionTableRow& Fallback);

	FString WheelEntryDisplayName(const FFableActionSlotData& Slot)
	{
		if (Slot.EntryId.IsEmpty()) return FString();

		const FString Payload = Slot.EntryId;
		if (Payload.StartsWith(TEXT("skill:"), ESearchCase::IgnoreCase))
		{
			FFableSkillDefinitionTableRow Fallback;
			if (const FFableSkillDefinitionTableRow* Skill = FindWheelSkillDefinition(Payload.RightChop(6), Fallback))
			{
				if (!Skill->DisplayName.IsEmpty()) return Skill->DisplayName;
			}
		}

		const FString RawName = Slot.EntryLabel.IsEmpty() ? Payload : Slot.EntryLabel;
		return RawName.IsEmpty() ? FString() : ToDisplayName(RawName);
	}

	UTexture2D* CreateAlphaFilteredTexture(TArray<FLinearColor> Pixels, int32 Width, int32 Height, const TCHAR* DebugName)
	{
		if (Pixels.Num() != Width * Height || Width <= 0 || Height <= 0)
		{
			return nullptr;
		}

		UTexture2D* Texture = UTexture2D::CreateTransient(Width, Height, PF_B8G8R8A8, FName(DebugName));
		if (Texture == nullptr || Texture->GetPlatformData() == nullptr)
		{
			return nullptr;
		}

		Texture->SRGB = true;
		Texture->NeverStream = true;
		Texture->LODGroup = TEXTUREGROUP_UI;
		Texture->Filter = TF_Trilinear;
		Texture->AddressX = TA_Clamp;
		Texture->AddressY = TA_Clamp;

		FTexturePlatformData* PlatformData = Texture->GetPlatformData();
		int32 Level = 0;
		for (;;)
		{
			if (Level > 0) PlatformData->Mips.Add(new FTexture2DMipMap());
			FTexture2DMipMap& Mip = PlatformData->Mips[Level++];
			Mip.SizeX = Width;
			Mip.SizeY = Height;
			Mip.SizeZ = 1;
			Mip.BulkData.Lock(LOCK_READ_WRITE);
			FColor* Output = reinterpret_cast<FColor*>(Mip.BulkData.Realloc(int64(Width) * Height * sizeof(FColor)));
			for (int32 Index = 0; Index < Pixels.Num(); ++Index)
			{
				Output[Index] = Pixels[Index].ToFColorSRGB();
			}
			Mip.BulkData.Unlock();

			if (Width == 1 && Height == 1) break;
			const int32 NextWidth = FMath::Max(1, Width / 2);
			const int32 NextHeight = FMath::Max(1, Height / 2);
			TArray<FLinearColor> Next;
			Next.SetNumUninitialized(NextWidth * NextHeight);
			for (int32 Y = 0; Y < NextHeight; ++Y)
			for (int32 X = 0; X < NextWidth; ++X)
			{
				FLinearColor Sum(0, 0, 0, 0);
				int32 Samples = 0;
				for (int32 SampleY = Y * Height / NextHeight; SampleY < (Y + 1) * Height / NextHeight; ++SampleY)
				for (int32 SampleX = X * Width / NextWidth; SampleX < (X + 1) * Width / NextWidth; ++SampleX)
				{
					const FLinearColor& Sample = Pixels[SampleY * Width + SampleX];
					Sum.R += Sample.R * Sample.A;
					Sum.G += Sample.G * Sample.A;
					Sum.B += Sample.B * Sample.A;
					Sum.A += Sample.A;
					++Samples;
				}
				Next[Y * NextWidth + X] = Sum.A > SMALL_NUMBER
					? FLinearColor(Sum.R / Sum.A, Sum.G / Sum.A, Sum.B / Sum.A, Sum.A / Samples)
					: FLinearColor::Transparent;
			}
			Pixels = MoveTemp(Next);
			Width = NextWidth;
			Height = NextHeight;
		}

		Texture->UpdateResource();
		return Texture;
	}

	UTexture2D* LoadQuickWheelTexture(const TCHAR* AssetPath, const FString& FileName, const TCHAR* DebugName)
	{
		const FString PngPath = FPaths::ProjectContentDir() / FileName;
		FImage Source;
		if (FImageUtils::LoadImage(*PngPath, Source))
		{
			Source.ChangeFormat(ERawImageFormat::RGBA32F, EGammaSpace::Linear);
			TArray<FLinearColor> Pixels;
			Pixels.Append(reinterpret_cast<const FLinearColor*>(Source.RawData.GetData()), Source.SizeX * Source.SizeY);
			return CreateAlphaFilteredTexture(MoveTemp(Pixels), Source.SizeX, Source.SizeY, DebugName);
		}

		if (UTexture2D* ImportedTexture = LoadObject<UTexture2D>(nullptr, AssetPath))
		{
			ImportedTexture->Filter = TF_Trilinear;
			return ImportedTexture;
		}
		return nullptr;
	}

	UTexture2D* LoadQuickWheelFrame(bool bCosmic)
	{
		static TWeakObjectPtr<UTexture2D> CachedFrame;
		static TWeakObjectPtr<UTexture2D> CachedCosmicFrame;
		TWeakObjectPtr<UTexture2D>& CachedTexture = bCosmic ? CachedCosmicFrame : CachedFrame;
		if (CachedTexture.IsValid()) return CachedTexture.Get();

		UTexture2D* Texture = bCosmic
			? LoadQuickWheelTexture(TEXT("/Game/Slate/Textures/Journal/CosmicWheel.CosmicWheel"), TEXT("Slate/Textures/Journal/CosmicWheel.png"), TEXT("CosmicWheelFiltered"))
			: LoadQuickWheelTexture(TEXT("/Game/Slate/Textures/QuickWheelFrame.QuickWheelFrame"), TEXT("Slate/Textures/QuickWheelFrame.png"), TEXT("QuickWheelFrameFiltered"));
		if (Texture == nullptr && bCosmic)
		{
			// Keep the wheel visible while the optional cosmic art is unavailable.
			return LoadQuickWheelFrame(false);
		}
		CachedTexture = Texture;
		return Texture;
	}

	UTexture2D* LoadQuickWheelNeedle()
	{
		static TWeakObjectPtr<UTexture2D> CachedNeedle;
		if (CachedNeedle.IsValid()) return CachedNeedle.Get();

		UTexture2D* Texture = LoadQuickWheelTexture(TEXT("/Game/Slate/Textures/QuickWheelNeedle.QuickWheelNeedle"), TEXT("Slate/Textures/QuickWheelNeedle.png"), TEXT("QuickWheelNeedleFiltered"));
		CachedNeedle = Texture;
		return Texture;
	}

	FString SkillSchoolArtName(EFableSkillCategory Category)
	{
		switch (Category)
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
		case EFableSkillCategory::Fire: return TEXT("Fire");
		case EFableSkillCategory::Water: return TEXT("Water");
		case EFableSkillCategory::Earth: return TEXT("Earth");
		case EFableSkillCategory::Air: return TEXT("Air");
		case EFableSkillCategory::TimeManipulation: return TEXT("Time");
		default: return TEXT("Unknown");
		}
	}

	UTexture2D* LoadSkillSchoolArt(EFableSkillCategory Category)
	{
		const FString Name = SkillSchoolArtName(Category);
		static TMap<FString, TStrongObjectPtr<UTexture2D>> Cache;
		if (const auto* Found = Cache.Find(Name)) return Found->Get();
		const FString AssetPath = FString::Printf(TEXT("/Game/Slate/Textures/Journal/%s.%s"), *Name, *Name);
		UTexture2D* Texture = LoadQuickWheelTexture(*AssetPath, FString::Printf(TEXT("Slate/Textures/Journal/%s.png"), *Name), *FString::Printf(TEXT("QuickWheel%sArt"), *Name));
		if (Texture) Cache.Add(Name, TStrongObjectPtr<UTexture2D>(Texture));
		return Texture;
	}

	const FFableSkillDefinitionTableRow* FindWheelSkillDefinition(const FString& SkillId, FFableSkillDefinitionTableRow& Fallback)
	{
		static TWeakObjectPtr<UDataTable> CachedSkillTable;
		UDataTable* SkillTable = CachedSkillTable.Get();
		if (SkillTable == nullptr)
		{
			SkillTable = LoadObject<UDataTable>(nullptr, TEXT("/Game/Data/DT_Skills.DT_Skills"));
			CachedSkillTable = SkillTable;
		}
		if (SkillTable != nullptr)
		{
			TArray<FFableSkillDefinitionTableRow*> Rows;
			SkillTable->GetAllRows(TEXT("FableTimeWheelWidget"), Rows);
			for (const FFableSkillDefinitionTableRow* Row : Rows)
				if (Row != nullptr && Row->SkillId.Equals(SkillId, ESearchCase::IgnoreCase))
				{
					Fallback = *Row;
					FFableSkillDefinitionTableRow Starter;
					if (FableSkillCatalog::TryGetStarterSkillDefinition(SkillId, Starter)) Fallback.Category = Starter.Category;
					return &Fallback;
				}
		}
		return FableSkillCatalog::TryGetStarterSkillDefinition(SkillId, Fallback) ? &Fallback : nullptr;
	}

	UTexture2D* WheelIconForPayload(const FString& Payload)
	{
		if (Payload.StartsWith(TEXT("item:"), ESearchCase::IgnoreCase))
		{
			return FableItemIcons::Get(Payload.RightChop(5));
		}
		if (!Payload.StartsWith(TEXT("skill:"), ESearchCase::IgnoreCase)) return nullptr;

		FFableSkillDefinitionTableRow Fallback;
		const FFableSkillDefinitionTableRow* Skill = FindWheelSkillDefinition(Payload.RightChop(6), Fallback);
		if (Skill == nullptr) return nullptr;
		if (!Skill->SkillIconTexture.IsNull())
		{
			if (UTexture2D* AuthoredIcon = Skill->SkillIconTexture.LoadSynchronous()) return AuthoredIcon;
		}
		return LoadSkillSchoolArt(Skill->Category);
	}
}

TSharedRef<SWidget> UFableTimeWheelWidget::RebuildWidget()
{
	if (WidgetTree != nullptr)
	{
		RootCanvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("TimeWheelRoot"));
		WidgetTree->RootWidget = RootCanvas;
	}
	return Super::RebuildWidget();
}

void UFableTimeWheelWidget::NativeConstruct()
{
	Super::NativeConstruct();
	SetVisibility(ESlateVisibility::Collapsed);
}

void UFableTimeWheelWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);
	if (!bOpen || bTargeting) return;
	InventoryRefreshAccumulator += InDeltaTime;
	if (InventoryRefreshAccumulator >= 0.1f)
	{
		InventoryRefreshAccumulator = 0.0f;
		UpdateWheelInventoryQuantities();
	}
}

void UFableTimeWheelWidget::Open(const TArray<FFableQuickWheelPageData>& InPages)
{
	Pages = InPages;
	PageIndex = FMath::Clamp(PageIndex, 0, FMath::Max(0, Pages.Num() - 1));
	SelectedSlot = INDEX_NONE;
	RightStickDirection = FVector2D(0.0f, -1.0f);
	bOpen = true;
	InventoryRefreshAccumulator = 0.0f;
	SetVisibility(ESlateVisibility::Visible);
	RebuildWheel();
}

void UFableTimeWheelWidget::Close()
{
	bOpen = false;
	if (SelectedEntryNameText != nullptr)
	{
		SelectedEntryNameText->SetVisibility(ESlateVisibility::Collapsed);
	}
	SetVisibility(ESlateVisibility::Collapsed);
}

void UFableTimeWheelWidget::SetPage(int32 InPageIndex)
{
	if (Pages.Num() == 0) return;
	PageIndex = (InPageIndex % Pages.Num() + Pages.Num()) % Pages.Num();
	SelectedSlot = INDEX_NONE;
	RebuildWheel();
}

void UFableTimeWheelWidget::SetElement(FName InElement) { Element = InElement; RebuildWheel(); }
void UFableTimeWheelWidget::SetCosmicWheel(bool bInCosmic)
{
	if (bCosmicWheel == bInCosmic)
	{
		return;
	}
	bCosmicWheel = bInCosmic;
	RebuildWheel();
}
void UFableTimeWheelWidget::SetGesture(FString InGesture) { Gesture = MoveTemp(InGesture); RebuildWheel(); }
void UFableTimeWheelWidget::SetTimeState(bool bInSlow, bool bInStopped) { bSlow = bInSlow; bStopped = bInStopped; RebuildWheel(); }
void UFableTimeWheelWidget::BeginTargeting(const FString& SkillLabel, const FVector& InLocation) { bOpen = true; bTargeting = true; TargetSkill = SkillLabel; TargetLocation = InLocation; SetVisibility(ESlateVisibility::Visible); RebuildWheel(); }
void UFableTimeWheelWidget::SetTargetLocation(const FVector& InLocation)
{
	if (FVector::DistSquared(TargetLocation, InLocation) < 1.f) return;
	TargetLocation = InLocation;
	FVector2D Projected;
	if (UWidgetLayoutLibrary::ProjectWorldLocationToWidgetPosition(GetOwningPlayer(), TargetLocation, Projected, true))
		for (UBorder* Line : TargetCursorLines)
			if (Line)
				if (auto* Slot = Cast<UCanvasPanelSlot>(Line->Slot)) Slot->SetPosition(Projected - GetCachedGeometry().GetLocalSize() * .5f);
}
void UFableTimeWheelWidget::EndTargeting() { bTargeting = false; TargetSkill.Reset(); RebuildWheel(); }

void UFableTimeWheelWidget::SetTargetPreview(FVector2D CursorPixels, FVector Location, FVector Normal, float Radius, bool bValid, bool bHit)
{
	TargetCursorPixels = CursorPixels; TargetLocation = Location; TargetNormal = Normal;
	TargetRadius = Radius; bTargetValid = bValid; bTargetHit = bHit;
}

int32 UFableTimeWheelWidget::NativePaint(const FPaintArgs& Args, const FGeometry& Geometry, const FSlateRect& CullingRect, FSlateWindowElementList& Elements, int32 Layer, const FWidgetStyle& Style, bool bEnabled) const
{
	Layer = Super::NativePaint(Args, Geometry, CullingRect, Elements, Layer, Style, bEnabled);
	if (!bTargeting) return Layer;
	const float Scale = FMath::Max(.1f, UWidgetLayoutLibrary::GetViewportScale(this));
	const FVector2D Center = TargetCursorPixels / Scale;
	const FLinearColor Color = bTargetValid ? FLinearColor(.95f, .79f, .37f, 1.f) : FLinearColor(1.f, .25f, .18f, 1.f);
	const auto DrawLine = [&](const TArray<FVector2D>& Points, float Width)
	{
		FSlateDrawElement::MakeLines(Elements, Layer + 1, Geometry.ToPaintGeometry(), Points, ESlateDrawEffect::None, Color, true, Width);
	};
	DrawLine({Center + FVector2D(-15,0), Center + FVector2D(-5,0)}, 2.f);
	DrawLine({Center + FVector2D(5,0), Center + FVector2D(15,0)}, 2.f);
	DrawLine({Center + FVector2D(0,-15), Center + FVector2D(0,-5)}, 2.f);
	DrawLine({Center + FVector2D(0,5), Center + FVector2D(0,15)}, 2.f);
	if (bTargetHit)
	{
		FVector AxisX, AxisY; TargetNormal.FindBestAxisVectors(AxisX, AxisY);
		TArray<FVector2D> Ring;
		for (int32 I = 0; I <= 48; ++I)
		{
			const float Angle = TWO_PI * I / 48.f;
			const FVector Point = TargetLocation + TargetNormal * 2.f + (AxisX * FMath::Cos(Angle) + AxisY * FMath::Sin(Angle)) * TargetRadius;
			FVector2D Projected;
			if (!UWidgetLayoutLibrary::ProjectWorldLocationToWidgetPosition(GetOwningPlayer(), Point, Projected, true)) { Ring.Reset(); break; }
			Ring.Add(Projected);
		}
		if (Ring.Num() > 1) DrawLine(Ring, 2.f);
	}
	return Layer + 1;
}

FVector2D UFableTimeWheelWidget::GetSocketPosition(int32 InSlot)
{
	// Shared by gameplay rendering and assignment hit testing. These centers are
	// derived from the 1254px CosmicWheel artwork at its 720px display size.
	static const FVector2D Positions[8] = {
		FVector2D(0.f, -247.f), FVector2D(205.f, -172.f),
		FVector2D(271.f, 0.f), FVector2D(205.f, 171.f),
		FVector2D(0.f, 247.f), FVector2D(-205.f, 171.f),
		FVector2D(-271.f, 0.f), FVector2D(-205.f, -172.f)
	};
	return Positions[FMath::Clamp(InSlot, 0, 7)];
}

void UFableTimeWheelWidget::SetSelectedSlot(int32 InSlot)
{
	SelectedSlot = InSlot == INDEX_NONE ? INDEX_NONE : (InSlot % 8 + 8) % 8;
	if (SelectedSlot != INDEX_NONE) RightStickDirection = GetSocketPosition(SelectedSlot).GetSafeNormal();
	UpdateWheelSelectionVisuals();
}

void UFableTimeWheelWidget::SetSelectionFromStick(const FVector2D& Stick)
{
	if (Stick.SizeSquared() < FMath::Square(QuickWheelStickDeadzone) || Pages.Num() == 0) return;
	const FVector2D NewDirection = Stick.GetSafeNormal();
	const bool bDirectionChanged = FVector2D::DotProduct(RightStickDirection, NewDirection) < 0.995f;
	// Slots are laid out clockwise from the top. Convert the stick angle from
	// screen-space (right = 0 radians) into that same top-first ordering.
	const float AngleFromTopClockwise = FMath::Fmod(FMath::Atan2(Stick.Y, Stick.X) + HALF_PI + TWO_PI, TWO_PI);
	const int32 NewSelectedSlot = FMath::FloorToInt((AngleFromTopClockwise + TWO_PI / 16.0f) / (TWO_PI / 8.0f)) % 8;
	const bool bSlotChanged = NewSelectedSlot != SelectedSlot;
	if (NewSelectedSlot != SelectedSlot)
	{
		const FVector2D CurrentSlotDirection = SelectedSlot == INDEX_NONE ? FVector2D::ZeroVector : GetSocketPosition(SelectedSlot).GetSafeNormal();
		if (SelectedSlot != INDEX_NONE && FVector2D::DotProduct(CurrentSlotDirection, NewDirection) >= QuickWheelSelectionHysteresisDot)
		{
			return;
		}
		SelectedSlot = NewSelectedSlot;
	}
	if (!bDirectionChanged && !bSlotChanged)
	{
		return;
	}
	RightStickDirection = NewDirection;
	UpdateWheelSelectionVisuals();
}

FString UFableTimeWheelWidget::GetSelectedPayload() const
{
	return Pages.IsValidIndex(PageIndex) && Pages[PageIndex].Slots.IsValidIndex(SelectedSlot)
		? Pages[PageIndex].Slots[SelectedSlot].EntryId : FString();
}

void UFableTimeWheelWidget::AddLabel(const FString& Text, const FVector2D& Position, const FVector2D& Size, const FLinearColor& Color, int32 FontSize, bool bBold)
{
	if (RootCanvas == nullptr || WidgetTree == nullptr) return;
	UTextBlock* Label = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Label->SetText(FText::FromString(Text));
	Label->SetColorAndOpacity(Color);
	Label->SetJustification(ETextJustify::Center);
	Label->SetAutoWrapText(true);
	Label->SetFont(FableBookStyle::Font(FontSize, bBold));
	if (UCanvasPanelSlot* Slot = RootCanvas->AddChildToCanvas(Label))
	{
		Slot->SetAnchors(FAnchors(0.5f, 0.5f));
		Slot->SetAlignment(FVector2D(0.5f, 0.5f));
		Slot->SetPosition(Position);
		Slot->SetSize(Size);
	}
}

void UFableTimeWheelWidget::AddWheelTile(const FString& LabelText, const FVector2D& Position, bool bSelected)
{
	if (RootCanvas == nullptr || WidgetTree == nullptr) return;
	(void)LabelText;

	UBorder* Tile = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
	const bool bCardinalTile = FMath::Abs(Position.X) < 1.0f && FMath::Abs(Position.Y) > 200.0f;
	const float TileSize = bCardinalTile ? 88.0f : 86.0f;
	Tile->SetBrush(FSlateRoundedBoxBrush(
		bSelected ? FableBookStyle::Parchment : FLinearColor(0.10f, 0.035f, 0.025f, 0.98f),
		TileSize * 0.5f,
		bSelected ? (bCosmicWheel ? FLinearColor(0.98f, 0.72f, 0.24f, 1.0f) : FableBookStyle::Gold) : FLinearColor(0.45f, 0.25f, 0.12f, 0.9f),
		bSelected ? 3.0f : 1.0f));
	Tile->SetPadding(FMargin(6.0f));
	Tile->SetHorizontalAlignment(HAlign_Fill);
	Tile->SetVerticalAlignment(VAlign_Fill);

	UCanvasPanel* TileCanvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass());
	Tile->SetContent(TileCanvas);
	const FString Payload = Pages.IsValidIndex(PageIndex) && Pages[PageIndex].Slots.IsValidIndex(WheelTiles.Num())
		? Pages[PageIndex].Slots[WheelTiles.Num()].EntryId : FString();
	if (!Payload.IsEmpty()) Tile->SetToolTipText(FText::FromString(ToDisplayName(LabelText.IsEmpty() ? Payload : LabelText)));
	if (UTexture2D* IconTexture = WheelIconForPayload(Payload))
	{
		const bool bItemIcon = Payload.StartsWith(TEXT("item:"));
		const float IconSize = bItemIcon ? 72.f : 78.f;
		UImage* Icon = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass());
		Icon->SetBrushFromTexture(IconTexture, true);
		Icon->SetColorAndOpacity(FLinearColor::White);
		Icon->SetDesiredSizeOverride(FVector2D(IconSize, IconSize));
		if (UCanvasPanelSlot* IconSlot = TileCanvas->AddChildToCanvas(Icon))
		{
			IconSlot->SetAnchors(FAnchors(0.5f, 0.5f));
			IconSlot->SetAlignment(FVector2D(0.5f, 0.5f));
			IconSlot->SetPosition(FVector2D(0.f, bItemIcon ? -8.f : 0.f));
			IconSlot->SetSize(FVector2D(IconSize, IconSize));
		}
		WheelTileIcons.Add(Icon);
	}
	else
	{
		WheelTileIcons.Add(nullptr);
	}

	const bool bItem = Payload.StartsWith(TEXT("item:"), ESearchCase::IgnoreCase);
	UBorder* QuantityBadge = nullptr;
	UTextBlock* QuantityLabel = nullptr;
	if (bItem)
	{
		QuantityBadge = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
		QuantityBadge->SetBrush(FSlateRoundedBoxBrush(FLinearColor(0.06f, 0.025f, 0.015f, 0.94f), 7.0f, FableBookStyle::Gold, 1.0f));
		QuantityLabel = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		QuantityLabel->SetText(FText::FromString(TEXT("0")));
		QuantityLabel->SetColorAndOpacity(FableBookStyle::Parchment);
		QuantityLabel->SetJustification(ETextJustify::Center);
		QuantityLabel->SetFont(FableBookStyle::Font(14, true));
		QuantityBadge->SetContent(QuantityLabel);
		if (UCanvasPanelSlot* BadgeSlot = TileCanvas->AddChildToCanvas(QuantityBadge))
		{
			BadgeSlot->SetAnchors(FAnchors(0.5f, 1.0f));
			BadgeSlot->SetAlignment(FVector2D(0.5f, 1.0f));
			BadgeSlot->SetPosition(FVector2D(0.0f, -2.0f));
			BadgeSlot->SetSize(FVector2D(34.0f, 20.0f));
		}
	}
	WheelTileQuantityBadges.Add(QuantityBadge);
	WheelTileQuantityLabels.Add(QuantityLabel);

	if (UCanvasPanelSlot* Slot = RootCanvas->AddChildToCanvas(Tile))
	{
		Slot->SetAnchors(FAnchors(0.5f, 0.5f));
		Slot->SetAlignment(FVector2D(0.5f, 0.5f));
		Slot->SetPosition(Position);
		Slot->SetSize(FVector2D(TileSize, TileSize));
	}
	WheelTiles.Add(Tile);
}

void UFableTimeWheelWidget::UpdateWheelSelectionVisuals()
{
	if (!bOpen)
	{
		return;
	}

	for (int32 Index = 0; Index < WheelTiles.Num(); ++Index)
	{
		UBorder* Tile = WheelTiles[Index];
		if (Tile == nullptr)
		{
			continue;
		}

		const FVector2D Position = GetSocketPosition(Index);
		const bool bSelected = Index == SelectedSlot;
		const bool bCardinalTile = FMath::Abs(Position.X) < 1.0f && FMath::Abs(Position.Y) > 200.0f;
	const float TileSize = bCardinalTile ? 88.0f : 86.0f;
		Tile->SetBrush(FSlateRoundedBoxBrush(
			bSelected ? FableBookStyle::Parchment : FLinearColor(0.10f, 0.035f, 0.025f, 0.98f),
			TileSize * 0.5f,
			bSelected ? (bCosmicWheel ? FLinearColor(0.98f, 0.72f, 0.24f, 1.0f) : FableBookStyle::Gold) : FLinearColor(0.45f, 0.25f, 0.12f, 0.9f),
			bSelected ? 3.0f : 1.0f));
	}

	if (SelectedEntryNameText != nullptr)
	{
		const FFableActionSlotData* SelectedEntry = Pages.IsValidIndex(PageIndex) && Pages[PageIndex].Slots.IsValidIndex(SelectedSlot)
			? &Pages[PageIndex].Slots[SelectedSlot] : nullptr;
		const FString DisplayName = SelectedEntry != nullptr ? WheelEntryDisplayName(*SelectedEntry) : FString();
		SelectedEntryNameText->SetText(FText::FromString(DisplayName));
		SelectedEntryNameText->SetVisibility(DisplayName.IsEmpty() ? ESlateVisibility::Collapsed : ESlateVisibility::HitTestInvisible);
	}

	if (NeedleLayer != nullptr)
	{
		NeedleLayer->SetVisibility(SelectedSlot == INDEX_NONE ? ESlateVisibility::Hidden : ESlateVisibility::HitTestInvisible);
		NeedleLayer->SetRenderTransformAngle(FMath::RadiansToDegrees(FMath::Atan2(RightStickDirection.Y, RightStickDirection.X)) + 90.0f);
	}
}

void UFableTimeWheelWidget::UpdateWheelInventoryQuantities()
{
	if (!bOpen || bTargeting || !Pages.IsValidIndex(PageIndex)) return;
	const UFableSaveSubsystem* SaveSubsystem = GetGameInstance()
		? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	FFableCharacterProfile Profile;
	const bool bHaveProfile = SaveSubsystem != nullptr && SaveSubsystem->TryGetActiveCharacterProfile(Profile);
	for (int32 Index = 0; Index < WheelTileQuantityLabels.Num(); ++Index)
	{
		UTextBlock* QuantityLabel = WheelTileQuantityLabels[Index];
		if (QuantityLabel == nullptr) continue;
		const FString Payload = Pages[PageIndex].Slots.IsValidIndex(Index) ? Pages[PageIndex].Slots[Index].EntryId : FString();
		const FString ItemId = Payload.StartsWith(TEXT("item:"), ESearchCase::IgnoreCase) ? Payload.RightChop(5) : FString();
		int64 TotalQuantity = 0;
		if (bHaveProfile && !ItemId.IsEmpty())
		{
			for (int32 SlotIndex = 0; SlotIndex < Profile.InventorySlots.Num(); ++SlotIndex)
			{
				if (Profile.InventorySlots[SlotIndex].Equals(ItemId, ESearchCase::IgnoreCase))
				{
					TotalQuantity += Profile.InventoryQuantities.IsValidIndex(SlotIndex)
						? FMath::Max(0, Profile.InventoryQuantities[SlotIndex]) : 0;
				}
			}
		}
		QuantityLabel->SetText(FText::AsNumber(TotalQuantity));
		if (WheelTileIcons.IsValidIndex(Index) && WheelTileIcons[Index] != nullptr)
		{
			WheelTileIcons[Index]->SetColorAndOpacity(TotalQuantity > 0 ? FLinearColor::White : FLinearColor(0.35f, 0.35f, 0.35f, 0.65f));
		}
	}
}

void UFableTimeWheelWidget::RebuildWheel()
{
	if (RootCanvas == nullptr || !bOpen) return;
	RootCanvas->ClearChildren();
	WheelTiles.Reset();
	TargetCursorLines.Reset();
	WheelTileIcons.Reset();
	WheelTileQuantityBadges.Reset();
	WheelTileQuantityLabels.Reset();
	NeedleLayer = nullptr;
	SelectedEntryNameText = nullptr;
	// Precision targeting is painted as a cursor and surface footprint only.
	if (bTargeting) return;
	const FLinearColor WheelGold = bCosmicWheel ? FLinearColor(0.98f, 0.72f, 0.24f, 1.0f) : FLinearColor(0.96f, 0.78f, 0.34f, 1.0f);
	const FLinearColor Muted(0.72f, 0.63f, 0.48f, 1.0f);
	const FLinearColor Accent = bCosmicWheel ? FLinearColor(0.70f, 0.38f, 0.98f, 1.0f) : ElementColor(Element);

	UBorder* Backdrop = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
	Backdrop->SetBrushColor(FLinearColor(0.015f, 0.008f, 0.006f, 0.86f));
	if (UCanvasPanelSlot* Slot = RootCanvas->AddChildToCanvas(Backdrop))
	{
		Slot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
		Slot->SetOffsets(FMargin(0.0f));
	}
	if (UTexture2D* FrameTexture = LoadQuickWheelFrame(bCosmicWheel))
	{
		UImage* Frame = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass());
		Frame->SetBrushFromTexture(FrameTexture, true);
		Frame->SetColorAndOpacity(FLinearColor::White);
		if (UCanvasPanelSlot* Slot = RootCanvas->AddChildToCanvas(Frame))
		{
			Slot->SetAnchors(FAnchors(0.5f, 0.5f));
			Slot->SetAlignment(FVector2D(0.5f, 0.5f));
			Slot->SetPosition(FVector2D(0.0f, 0.0f));
			Slot->SetSize(FVector2D(720.0f, 720.0f));
		}
	}

	if (UTexture2D* NeedleTexture = LoadQuickWheelNeedle())
	{
		// Keep the generated artwork inside an explicit layer. SetBrushFromTexture can
		// retain the source texture's 1024x1536 desired size on some Slate paths, which
		// makes a rotated needle escape the viewport even when its canvas slot is small.
		NeedleLayer = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("QuickWheelNeedleLayer"));
		if (UCanvasPanelSlot* NeedleSlot = RootCanvas->AddChildToCanvas(NeedleLayer))
		{
			NeedleSlot->SetAnchors(FAnchors(0.5f, 0.5f));
			NeedleSlot->SetAlignment(FVector2D(0.5f, 0.5f));
			NeedleSlot->SetPosition(FVector2D::ZeroVector);
			NeedleSlot->SetSize(FVector2D(204.0f, 204.0f));
		}

		UImage* Needle = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("QuickWheelNeedleImage"));
		FSlateBrush NeedleBrush;
		NeedleBrush.SetResourceObject(NeedleTexture);
		NeedleBrush.DrawAs = ESlateBrushDrawType::Image;
		NeedleBrush.ImageSize = FVector2D(204.0f, 204.0f);
		Needle->SetBrush(NeedleBrush);
		Needle->SetDesiredSizeOverride(FVector2D(204.0f, 204.0f));
		Needle->SetColorAndOpacity(FLinearColor(1.0f, 0.88f, 0.62f, 0.95f));
		if (UCanvasPanelSlot* ImageSlot = NeedleLayer->AddChildToCanvas(Needle))
		{
			ImageSlot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
			ImageSlot->SetOffsets(FMargin(0.0f));
		}
		NeedleLayer->SetRenderTransformAngle(FMath::RadiansToDegrees(FMath::Atan2(RightStickDirection.Y, RightStickDirection.X)) + 90.0f);
		NeedleLayer->SetRenderTransformPivot(FVector2D(0.5f, 0.5f));
		NeedleLayer->SetVisibility(SelectedSlot == INDEX_NONE ? ESlateVisibility::Hidden : ESlateVisibility::HitTestInvisible);
	}

	SelectedEntryNameText = WidgetTree->ConstructWidget<UTextBlock>();
	SelectedEntryNameText->SetColorAndOpacity(WheelGold);
	SelectedEntryNameText->SetJustification(ETextJustify::Center);
	SelectedEntryNameText->SetAutoWrapText(true);
	SelectedEntryNameText->SetFont(FableBookStyle::Font(18, true));
	if (UCanvasPanelSlot* NameSlot = RootCanvas->AddChildToCanvas(SelectedEntryNameText))
	{
		NameSlot->SetAnchors(FAnchors(0.5f, 0.5f));
		NameSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		// The name sits in the open upper interior: below the top socket and
		// above the needle's inner end, without competing with the frame art.
		NameSlot->SetPosition(FVector2D(0.0f, -136.0f));
		NameSlot->SetSize(FVector2D(300.0f, 38.0f));
	}

	// These offsets are matched to the eight socket centers in the 720px display
	// of CosmicWheel.png. The generated frame is intentionally not a perfect octagon.
	for (int32 Index = 0; Index < 8; ++Index)
	{
		const FVector2D Position = GetSocketPosition(Index);
		const bool bSelected = Index == SelectedSlot;
		FString Label = Pages.IsValidIndex(PageIndex) && Pages[PageIndex].Slots.IsValidIndex(Index)
			? Pages[PageIndex].Slots[Index].EntryLabel : FString();
		AddWheelTile(Label, Position, bSelected);
	}
	UpdateWheelInventoryQuantities();
	UpdateWheelSelectionVisuals();
}
