#include "FableBookStyle.h"
#include "Engine/Texture2D.h"
#include "UObject/StrongObjectPtr.h"

namespace
{
UTexture2D* ButtonArt(bool bCover)
{
	static TStrongObjectPtr<UTexture2D> Paper, Leather;
	TStrongObjectPtr<UTexture2D>& Cached = bCover ? Leather : Paper;
	if (Cached.IsValid()) return Cached.Get();
	constexpr int32 W = 256, H = 64;
	TArray<FColor> Pixels; Pixels.Init(FColor::Transparent, W * H);
	const FColor Edge(126, 88, 40), Gold(194, 153, 82), Highlight(225, 196, 131);
	for (int32 Y = 2; Y < H-2; ++Y)
	for (int32 X = 2; X < W-2; ++X)
	{
		const int32 DX = FMath::Min(X-2, W-3-X), DY = FMath::Min(Y-2, H-3-Y);
		if (DX + DY < 6) continue;
		const int32 Border = FMath::Min(DX, DY);
		FColor Color = bCover ? FColor(91, 47, 32) : FColor(208, 186, 142);
		if (Border == 0 || DX + DY == 6) Color = Edge;
		else if (Border == 1) Color = Highlight;
		else if (Border == 2 || Border == 5) Color = Gold;
		else if (Border == 6) Color = Edge;
		// Raised upper bevel, darker lower bevel, and restrained material grain.
		const float Grain = float((X * 17 + Y * 31 + X * Y * 3) % 13 - 6);
		float Shade = 1.f + 0.11f * (1.f - 2.f * float(Y) / H);
		if (Border < 7) Shade *= Y < H/2 ? 1.15f : 0.70f;
		Color.R = uint8(FMath::Clamp(Color.R * Shade + Grain, 0.f, 255.f));
		Color.G = uint8(FMath::Clamp(Color.G * Shade + Grain, 0.f, 255.f));
		Color.B = uint8(FMath::Clamp(Color.B * Shade + Grain, 0.f, 255.f));
		Pixels[Y*W+X] = Color;
	}
	// Small inset diamonds form the corner tooling; nine-slicing preserves their proportions.
	for (int32 CX : {13, W-14}) for (int32 CY : {13, H-14})
	for (int32 Y=-4; Y<=4; ++Y) for (int32 X=-4; X<=4; ++X)
		if (FMath::Abs(X)+FMath::Abs(Y)<=4) Pixels[(CY+Y)*W+CX+X] = Gold;
	UTexture2D* Texture = UTexture2D::CreateTransient(W,H,PF_B8G8R8A8);
	Texture->SRGB = true;
	Texture->NeverStream = true;
	Texture->LODGroup = TEXTUREGROUP_UI;
	void* Dest = Texture->GetPlatformData()->Mips[0].BulkData.Lock(LOCK_READ_WRITE);
	FMemory::Memcpy(Dest,Pixels.GetData(),Pixels.Num()*sizeof(FColor));
	Texture->GetPlatformData()->Mips[0].BulkData.Unlock();
	Texture->UpdateResource();
	Cached.Reset(Texture);
	return Texture;
}
}

void FableBookStyle::ApplyButton(UButton* Button, bool bCover)
{
	if (!Button) return;
	FSlateBrush Brush;
	Brush.SetResourceObject(ButtonArt(bCover));
	Brush.ImageSize = FVector2D(256.f,64.f);
	Brush.DrawAs = ESlateBrushDrawType::Box;
	Brush.Margin = FMargin(20.f/256.f,20.f/64.f);
	FButtonStyle Style;
	Style.SetNormal(Brush);
	Brush.TintColor = FLinearColor(1.15f,1.1f,0.96f,1.f);
	Style.SetHovered(Brush);
	Brush.TintColor = FLinearColor(0.72f,0.68f,0.58f,1.f);
	Style.SetPressed(Brush);
	Brush.TintColor = FLinearColor(0.7f,0.7f,0.7f,0.5f);
	Style.SetDisabled(Brush);
	Style.SetNormalPadding(FMargin(0.f));
	Style.SetPressedPadding(FMargin(0.f,1.f,0.f,0.f));
	Button->SetStyle(Style);
	Button->SetBackgroundColor(FLinearColor::White);
}
