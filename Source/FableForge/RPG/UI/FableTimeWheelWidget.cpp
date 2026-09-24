#include "RPG/UI/FableTimeWheelWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/Border.h"
#include "Components/Image.h"
#include "Components/TextBlock.h"
#include "Brushes/SlateRoundedBoxBrush.h"
#include "Engine/Texture2D.h"
#include "IImageWrapper.h"
#include "IImageWrapperModule.h"
#include "Modules/ModuleManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "RPG/UI/FableBookStyle.h"
#include "Styling/SlateTypes.h"
#include "Styling/SlateColor.h"

namespace
{
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

	UTexture2D* LoadQuickWheelFrame()
	{
		static TWeakObjectPtr<UTexture2D> CachedFrame;
		if (CachedFrame.IsValid()) return CachedFrame.Get();

		if (UTexture2D* ImportedFrame = LoadObject<UTexture2D>(nullptr, TEXT("/Game/Slate/Textures/QuickWheelFrame.QuickWheelFrame")))
		{
			CachedFrame = ImportedFrame;
			return ImportedFrame;
		}

		TArray<uint8> Compressed;
		const FString FramePath = FPaths::ProjectContentDir() / TEXT("Slate/Textures/QuickWheelFrame.png");
		if (!FFileHelper::LoadFileToArray(Compressed, *FramePath)) return nullptr;

		IImageWrapperModule& ImageWrapperModule = FModuleManager::LoadModuleChecked<IImageWrapperModule>(TEXT("ImageWrapper"));
		const TSharedPtr<IImageWrapper> Wrapper = ImageWrapperModule.CreateImageWrapper(EImageFormat::PNG);
		if (!Wrapper.IsValid() || !Wrapper->SetCompressed(Compressed.GetData(), Compressed.Num())) return nullptr;

		TArray<uint8> Raw;
		if (!Wrapper->GetRaw(ERGBFormat::BGRA, 8, Raw)) return nullptr;
		UTexture2D* Texture = UTexture2D::CreateTransient(Wrapper->GetWidth(), Wrapper->GetHeight(), PF_B8G8R8A8);
		if (!Texture) return nullptr;
		Texture->SRGB = true;
		Texture->NeverStream = true;
		void* TextureData = Texture->GetPlatformData()->Mips[0].BulkData.Lock(LOCK_READ_WRITE);
		FMemory::Memcpy(TextureData, Raw.GetData(), Raw.Num());
		Texture->GetPlatformData()->Mips[0].BulkData.Unlock();
		Texture->UpdateResource();
		CachedFrame = Texture;
		return Texture;
	}

	UTexture2D* LoadQuickWheelNeedle()
	{
		static TWeakObjectPtr<UTexture2D> CachedNeedle;
		if (CachedNeedle.IsValid()) return CachedNeedle.Get();

		if (UTexture2D* ImportedNeedle = LoadObject<UTexture2D>(nullptr, TEXT("/Game/Slate/Textures/QuickWheelNeedle.QuickWheelNeedle")))
		{
			CachedNeedle = ImportedNeedle;
			return ImportedNeedle;
		}

		TArray<uint8> Compressed;
		const FString NeedlePath = FPaths::ProjectContentDir() / TEXT("Slate/Textures/QuickWheelNeedle.png");
		if (!FFileHelper::LoadFileToArray(Compressed, *NeedlePath)) return nullptr;

		IImageWrapperModule& ImageWrapperModule = FModuleManager::LoadModuleChecked<IImageWrapperModule>(TEXT("ImageWrapper"));
		const TSharedPtr<IImageWrapper> Wrapper = ImageWrapperModule.CreateImageWrapper(EImageFormat::PNG);
		if (!Wrapper.IsValid() || !Wrapper->SetCompressed(Compressed.GetData(), Compressed.Num())) return nullptr;

		TArray<uint8> Raw;
		if (!Wrapper->GetRaw(ERGBFormat::BGRA, 8, Raw)) return nullptr;
		UTexture2D* Texture = UTexture2D::CreateTransient(Wrapper->GetWidth(), Wrapper->GetHeight(), PF_B8G8R8A8);
		if (!Texture) return nullptr;
		Texture->SRGB = true;
		Texture->NeverStream = true;
		void* TextureData = Texture->GetPlatformData()->Mips[0].BulkData.Lock(LOCK_READ_WRITE);
		FMemory::Memcpy(TextureData, Raw.GetData(), Raw.Num());
		Texture->GetPlatformData()->Mips[0].BulkData.Unlock();
		Texture->UpdateResource();
		CachedNeedle = Texture;
		return Texture;
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

void UFableTimeWheelWidget::Open(const TArray<FFableQuickWheelPageData>& InPages)
{
	Pages = InPages;
	PageIndex = FMath::Clamp(PageIndex, 0, FMath::Max(0, Pages.Num() - 1));
	SelectedSlot = 0;
	RightStickDirection = FVector2D(0.0f, -1.0f);
	bOpen = true;
	SetVisibility(ESlateVisibility::Visible);
	RebuildWheel();
}

void UFableTimeWheelWidget::Close()
{
	bOpen = false;
	SetVisibility(ESlateVisibility::Collapsed);
}

void UFableTimeWheelWidget::SetPage(int32 InPageIndex)
{
	if (Pages.Num() == 0) return;
	PageIndex = (InPageIndex % Pages.Num() + Pages.Num()) % Pages.Num();
	SelectedSlot = 0;
	RebuildWheel();
}

void UFableTimeWheelWidget::SetElement(FName InElement) { Element = InElement; RebuildWheel(); }
void UFableTimeWheelWidget::SetGesture(FString InGesture) { Gesture = MoveTemp(InGesture); RebuildWheel(); }
void UFableTimeWheelWidget::SetTimeState(bool bInSlow, bool bInStopped) { bSlow = bInSlow; bStopped = bInStopped; RebuildWheel(); }
void UFableTimeWheelWidget::BeginTargeting(const FString& SkillLabel, const FVector& InLocation) { bTargeting = true; TargetSkill = SkillLabel; TargetLocation = InLocation; SetVisibility(ESlateVisibility::Visible); RebuildWheel(); }
void UFableTimeWheelWidget::SetTargetLocation(const FVector& InLocation)
{
	if (FVector::DistSquared(TargetLocation, InLocation) < FMath::Square(45.0f)) return;
	TargetLocation = InLocation;
	RebuildWheel();
}
void UFableTimeWheelWidget::EndTargeting() { bTargeting = false; TargetSkill.Reset(); RebuildWheel(); }

FVector2D UFableTimeWheelWidget::GetSocketPosition(int32 InSlot)
{
	// Shared by gameplay rendering and assignment hit testing.
	static const FVector2D Positions[8] = {
		FVector2D(0.f, -211.f), FVector2D(177.f, -149.f),
		FVector2D(232.f, 0.f), FVector2D(177.f, 147.f),
		FVector2D(0.f, 210.f), FVector2D(-177.f, 147.f),
		FVector2D(-232.f, 0.f), FVector2D(-177.f, -149.f)
	};
	return Positions[FMath::Clamp(InSlot, 0, 7)];
}

void UFableTimeWheelWidget::SetSelectedSlot(int32 InSlot)
{
	SelectedSlot = (InSlot % 8 + 8) % 8;
	RightStickDirection = GetSocketPosition(SelectedSlot).GetSafeNormal();
	RebuildWheel();
}

void UFableTimeWheelWidget::SetSelectionFromStick(const FVector2D& Stick)
{
	if (Stick.SizeSquared() < 0.18f || Pages.Num() == 0) return;
	const FVector2D NewDirection = Stick.GetSafeNormal();
	const bool bDirectionChanged = FVector2D::DotProduct(RightStickDirection, NewDirection) < 0.995f;
	RightStickDirection = NewDirection;
	// Slots are laid out clockwise from the top. Convert the stick angle from
	// screen-space (right = 0 radians) into that same top-first ordering.
	const float AngleFromTopClockwise = FMath::Fmod(FMath::Atan2(Stick.Y, Stick.X) + HALF_PI + TWO_PI, TWO_PI);
	const int32 NewSelectedSlot = FMath::FloorToInt((AngleFromTopClockwise + TWO_PI / 16.0f) / (TWO_PI / 8.0f)) % 8;
	if (NewSelectedSlot != SelectedSlot || bDirectionChanged)
	{
		SelectedSlot = NewSelectedSlot;
		RebuildWheel();
	}
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

	UBorder* Tile = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
	const FLinearColor Accent = ElementColor(Element);
	const bool bCardinalTile = FMath::Abs(Position.X) < 1.0f && FMath::Abs(Position.Y) > 200.0f;
	const float TileSize = bCardinalTile ? 108.0f : 96.0f;
	Tile->SetBrush(FSlateRoundedBoxBrush(
		bSelected ? FableBookStyle::Parchment : FLinearColor(0.10f, 0.035f, 0.025f, 0.98f),
		TileSize * 0.5f,
		bSelected ? FableBookStyle::Gold : FLinearColor(0.45f, 0.25f, 0.12f, 0.9f),
		bSelected ? 3.0f : 1.0f));
	Tile->SetPadding(FMargin(6.0f));
	Tile->SetHorizontalAlignment(HAlign_Center);
	Tile->SetVerticalAlignment(VAlign_Center);

	UTextBlock* Label = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	FString DisplayText = ToDisplayName(LabelText);
	DisplayText.ReplaceInline(TEXT(" "), TEXT("\n"));
	Label->SetText(FText::FromString(DisplayText));
	Label->SetColorAndOpacity(bSelected ? FableBookStyle::Ink : FableBookStyle::Parchment);
	Label->SetJustification(ETextJustify::Center);
	Label->SetAutoWrapText(false);
	Label->SetFont(FableBookStyle::Font(bSelected ? 14 : 12, true));
	Tile->SetContent(Label);

	if (UCanvasPanelSlot* Slot = RootCanvas->AddChildToCanvas(Tile))
	{
		Slot->SetAnchors(FAnchors(0.5f, 0.5f));
		Slot->SetAlignment(FVector2D(0.5f, 0.5f));
		Slot->SetPosition(Position);
		Slot->SetSize(FVector2D(TileSize, TileSize));
	}
}

void UFableTimeWheelWidget::RebuildWheel()
{
	if (RootCanvas == nullptr || !bOpen) return;
	RootCanvas->ClearChildren();
	const FLinearColor Gold(0.96f, 0.78f, 0.34f, 1.0f);
	const FLinearColor Muted(0.72f, 0.63f, 0.48f, 1.0f);
	const FLinearColor Accent = ElementColor(Element);

	UBorder* Backdrop = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
	Backdrop->SetBrushColor(FLinearColor(0.015f, 0.008f, 0.006f, 0.86f));
	if (UCanvasPanelSlot* Slot = RootCanvas->AddChildToCanvas(Backdrop))
	{
		Slot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
		Slot->SetOffsets(FMargin(0.0f));
	}
	if (bTargeting)
	{
		AddLabel(TEXT("TIME FOCUS"), FVector2D(0, -120), FVector2D(800, 42), Gold, 26);
		AddLabel(FString::Printf(TEXT("Choose a target for  %s"), *ToDisplayName(TargetSkill)), FVector2D(0, -68), FVector2D(900, 44), FableBookStyle::Parchment, 20, false);
		AddLabel(TEXT("✦"), FVector2D(0, 0), FVector2D(120, 120), Accent);
		AddLabel(FString::Printf(TEXT("%.0f   /   %.0f   /   %.0f"), TargetLocation.X, TargetLocation.Y, TargetLocation.Z), FVector2D(0, 85), FVector2D(700, 36), Muted, 16, false);
		AddLabel(TEXT("RIGHT STICK  AIM        R2  CONFIRM        CIRCLE  CANCEL"), FVector2D(0, 145), FVector2D(1000, 36), Muted, 15, false);
		return;
	}
	if (UTexture2D* FrameTexture = LoadQuickWheelFrame())
	{
		UImage* Frame = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass());
		Frame->SetBrushFromTexture(FrameTexture, true);
		Frame->SetColorAndOpacity(FLinearColor(1.0f, 0.90f, 0.72f, 0.92f));
		if (UCanvasPanelSlot* Slot = RootCanvas->AddChildToCanvas(Frame))
		{
			Slot->SetAnchors(FAnchors(0.5f, 0.5f));
			Slot->SetAlignment(FVector2D(0.5f, 0.5f));
			Slot->SetPosition(FVector2D(0.0f, 0.0f));
			Slot->SetSize(FVector2D(620.0f, 620.0f));
		}
	}

	if (UTexture2D* NeedleTexture = LoadQuickWheelNeedle())
	{
		// Keep the generated artwork inside an explicit layer. SetBrushFromTexture can
		// retain the source texture's 1024x1536 desired size on some Slate paths, which
		// makes a rotated needle escape the viewport even when its canvas slot is small.
		UCanvasPanel* NeedleLayer = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("QuickWheelNeedleLayer"));
		if (UCanvasPanelSlot* NeedleSlot = RootCanvas->AddChildToCanvas(NeedleLayer))
		{
			NeedleSlot->SetAnchors(FAnchors(0.5f, 0.5f));
			NeedleSlot->SetAlignment(FVector2D(0.5f, 0.5f));
			NeedleSlot->SetPosition(FVector2D::ZeroVector);
			NeedleSlot->SetSize(FVector2D(170.0f, 170.0f));
		}

		UImage* Needle = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("QuickWheelNeedleImage"));
		FSlateBrush NeedleBrush;
		NeedleBrush.SetResourceObject(NeedleTexture);
		NeedleBrush.DrawAs = ESlateBrushDrawType::Image;
		NeedleBrush.ImageSize = FVector2D(170.0f, 170.0f);
		Needle->SetBrush(NeedleBrush);
		Needle->SetDesiredSizeOverride(FVector2D(170.0f, 170.0f));
		Needle->SetColorAndOpacity(FLinearColor(1.0f, 0.88f, 0.62f, 0.95f));
		if (UCanvasPanelSlot* ImageSlot = NeedleLayer->AddChildToCanvas(Needle))
		{
			ImageSlot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
			ImageSlot->SetOffsets(FMargin(0.0f));
		}
		NeedleLayer->SetRenderTransformAngle(FMath::RadiansToDegrees(FMath::Atan2(RightStickDirection.Y, RightStickDirection.X)) + 90.0f);
		NeedleLayer->SetRenderTransformPivot(FVector2D(0.5f, 0.5f));
	}

	// These offsets are matched to the eight socket centers in QuickWheelFrame.png.
	// The generated frame is intentionally not a mathematically perfect octagon.
	for (int32 Index = 0; Index < 8; ++Index)
	{
		const FVector2D Position = GetSocketPosition(Index);
		const bool bSelected = Index == SelectedSlot;
		FString Label = Pages.IsValidIndex(PageIndex) && Pages[PageIndex].Slots.IsValidIndex(Index)
			? Pages[PageIndex].Slots[Index].EntryLabel : FString();
		if (Label.IsEmpty()) Label = TEXT("Empty slot");
		AddWheelTile(Label, Position, bSelected);
	}
}
