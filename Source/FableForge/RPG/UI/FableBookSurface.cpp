#include "FableBookSurface.h"
#include "FableBookStyle.h"
#include "Rendering/DrawElements.h"
#include "Styling/CoreStyle.h"
#include "Widgets/SLeafWidget.h"
#include "ImageUtils.h"
#include "Engine/Texture2D.h"
#include "Misc/Paths.h"
#include "UObject/StrongObjectPtr.h"

class SFableBookSurface : public SLeafWidget
{
public:
	SLATE_BEGIN_ARGS(SFableBookSurface) {} SLATE_END_ARGS()
	void Construct(const FArguments&)
	{
		SetVisibility(EVisibility::HitTestInvisible);
		static TStrongObjectPtr<UTexture2D> Texture;
		if (!Texture.IsValid()) Texture.Reset(FImageUtils::ImportFileAsTexture2D(FPaths::ProjectContentDir() / TEXT("Slate/Textures/OpenJournal.png")));
		OpenBrush.SetResourceObject(Texture.Get());
		OpenBrush.DrawAs = ESlateBrushDrawType::Image;
		static TStrongObjectPtr<UTexture2D> Cover;
		if (!Cover.IsValid()) Cover.Reset(FImageUtils::ImportFileAsTexture2D(FPaths::ProjectContentDir() / TEXT("Slate/Textures/ClosedJournal.png")));
		CoverBrush.SetResourceObject(Cover.Get());
		CoverBrush.DrawAs = ESlateBrushDrawType::Image;
	}
	FSlateBrush OpenBrush, CoverBrush;
	bool bOpen = true;
	virtual FVector2D ComputeDesiredSize(float) const override { return FVector2D(bOpen ? 1200.f : 660.f, 780.f); }
	virtual int32 OnPaint(const FPaintArgs&, const FGeometry& Geometry, const FSlateRect&, FSlateWindowElementList& Out,
		int32 Layer, const FWidgetStyle& WidgetStyle, bool) const override
	{
		const FSlateBrush& ArtBrush = bOpen ? OpenBrush : CoverBrush;
		if (ArtBrush.GetResourceObject())
		{
			FSlateDrawElement::MakeBox(Out, Layer, Geometry.ToPaintGeometry(), &ArtBrush,
				ESlateDrawEffect::None, WidgetStyle.GetColorAndOpacityTint());
			return Layer;
		}
		const FVector2D Size = Geometry.GetLocalSize();
		const float W = bOpen ? 1200.f : 660.f, H = 780.f;
		const FVector2D Scale(Size.X / W, Size.Y / H);
		const FSlateBrush* White = FCoreStyle::Get().GetBrush("WhiteBrush");
		auto Rect = [&](float X, float Y, float Width, float Height, FLinearColor Color)
		{
			FSlateDrawElement::MakeBox(Out, Layer, Geometry.ToPaintGeometry(FVector2D(Width * Scale.X, Height * Scale.Y),
				FSlateLayoutTransform(FVector2D(X * Scale.X, Y * Scale.Y))), White, ESlateDrawEffect::None, Color * WidgetStyle.GetColorAndOpacityTint());
		};
		auto Line = [&](TArray<FVector2D> Points, FLinearColor Color, float Thickness = 1.f)
		{
			for (FVector2D& Point : Points) Point *= Scale;
			FSlateDrawElement::MakeLines(Out, Layer, Geometry.ToPaintGeometry(), Points, ESlateDrawEffect::None,
				Color * WidgetStyle.GetColorAndOpacityTint(), true, Thickness * FMath::Min(Scale.X, Scale.Y));
		};
		auto Frame = [&](float X, float Y, float Width, float Height, FLinearColor Color, float Thickness = 1.f)
		{
			Line({{X,Y},{X+Width,Y},{X+Width,Y+Height},{X,Y+Height},{X,Y}}, Color, Thickness);
		};
		// Continuous gradients remain smooth when the book is scaled down.
		auto Gradient = [&](float X, float Y, float Width, float Height, TArray<FSlateGradientStop> Stops, bool bAcross = true)
		{
			for (FSlateGradientStop& Stop : Stops)
			{
				Stop.Position = FVector2f(Stop.Position.X * Width * Scale.X, Stop.Position.Y * Height * Scale.Y);
				Stop.Color *= WidgetStyle.GetColorAndOpacityTint();
			}
			FSlateDrawElement::MakeGradient(Out, Layer, Geometry.ToPaintGeometry(FVector2D(Width * Scale.X, Height * Scale.Y),
				FSlateLayoutTransform(FVector2D(X * Scale.X, Y * Scale.Y))), MoveTemp(Stops), bAcross ? Orient_Vertical : Orient_Horizontal);
		};
		// Soft cast shadow, leather boards, then the individual leaves.
		for (int32 I = 14; I > 0; --I)
			Rect(18.f-I, 22.f-I*0.3f, W-30.f+I*2.f, H-37.f+I, FLinearColor(0.015f,0.007f,0.003f,0.025f));
		++Layer;
		Rect(11, 10, W-22, H-25, FableBookStyle::Oxblood);
		Frame(13, 12, W-26, H-29, FLinearColor(0.38f,0.20f,0.075f), 2.f);
		if (bOpen)
		{
			for (int32 I=5; I>=0; --I)
			{
				Rect(23+I, 20+I, W-46, H-45, FLinearColor(0.52f+I*0.035f,0.43f+I*0.035f,0.30f+I*0.03f));
				Line({{28.f+I, H-27.f+I},{W/2,H-19.f+I},{W-27.f+I,H-27.f+I}},FLinearColor(0.37f,0.28f,0.16f,0.5f));
			}
			++Layer;
			Rect(25, 22, W-50, H-57, FableBookStyle::Parchment);
			// Continuous page shading prevents dark strip seams at fractional UI scales.
			Gradient(25,22,W/2-25,H-57, {
				{FVector2f(0,0),FLinearColor(0.60f,0.47f,0.29f)},
				{FVector2f(0.035f,0),FLinearColor(0.84f,0.75f,0.57f)},
				{FVector2f(0.22f,0),FLinearColor(0.94f,0.87f,0.71f)},
				{FVector2f(0.64f,0),FLinearColor(0.89f,0.80f,0.63f)},
				{FVector2f(0.89f,0),FLinearColor(0.76f,0.65f,0.47f)},
				{FVector2f(0.975f,0),FLinearColor(0.49f,0.36f,0.21f)},
				{FVector2f(1,0),FLinearColor(0.28f,0.17f,0.09f)}});
			Gradient(W/2,22,W/2-25,H-57, {
				{FVector2f(0,0),FLinearColor(0.32f,0.20f,0.11f)},
				{FVector2f(0.025f,0),FLinearColor(0.65f,0.52f,0.34f)},
				{FVector2f(0.12f,0),FLinearColor(0.91f,0.82f,0.64f)},
				{FVector2f(0.32f,0),FLinearColor(0.97f,0.90f,0.74f)},
				{FVector2f(0.77f,0),FLinearColor(0.88f,0.78f,0.60f)},
				{FVector2f(0.97f,0),FLinearColor(0.79f,0.67f,0.49f)},
				{FVector2f(1,0),FLinearColor(0.58f,0.43f,0.26f)}});
			Gradient(25,22,W-50,H-57, {
				{FVector2f(0,0),FLinearColor(0.28f,0.14f,0.04f,0.13f)},
				{FVector2f(0,0.055f),FLinearColor(1.f,0.95f,0.80f,0.025f)},
				{FVector2f(0,0.8f),FLinearColor(0.25f,0.12f,0.03f,0.f)},
				{FVector2f(0,1),FLinearColor(0.25f,0.12f,0.03f,0.10f)}},false);
			Line({{27,23},{W/2-6,23}},FLinearColor(1.f,0.93f,0.75f,0.7f));
			Line({{W/2+7,23},{W-27,23}},FLinearColor(1.f,0.93f,0.75f,0.7f));
			Line({{26,H-35},{W/2,H-30},{W-26,H-35}},FLinearColor(0.31f,0.21f,0.12f,0.7f));
			for (float PageX : {48.f, W/2+34.f})
			{
				const float PageW = W/2-82.f;
				Line({{PageX,72},{PageX,47},{PageX+26,47}},FableBookStyle::Gold,1.2f);
				Line({{PageX+PageW-26,47},{PageX+PageW,47},{PageX+PageW,72}},FableBookStyle::Gold,1.2f);
				Line({{PageX,H-83},{PageX,H-58},{PageX+26,H-58}},FableBookStyle::Gold,1.2f);
				Line({{PageX+PageW-26,H-58},{PageX+PageW,H-58},{PageX+PageW,H-83}},FableBookStyle::Gold,1.2f);
				Line({{PageX+PageW/2-30,H-57},{PageX+PageW/2-7,H-57},{PageX+PageW/2,H-62},{PageX+PageW/2+7,H-57},{PageX+PageW/2+30,H-57}},FLinearColor(0.38f,0.23f,0.08f,0.65f));
			}
		}
		else
		{
			Gradient(19,16,W-38,H-38, {
				{FVector2f(0,0),FLinearColor(0.075f,0.016f,0.011f)},
				{FVector2f(0.15f,0),FLinearColor(0.21f,0.065f,0.038f)},
				{FVector2f(0.45f,0),FLinearColor(0.18f,0.047f,0.027f)},
				{FVector2f(0.94f,0),FLinearColor(0.10f,0.024f,0.016f)},
				{FVector2f(1,0),FLinearColor(0.035f,0.008f,0.005f)}});
			Gradient(20,17,55,H-41, {
				{FVector2f(0,0),FLinearColor(0.045f,0.011f,0.007f)},
				{FVector2f(0.42f,0),FLinearColor(0.22f,0.075f,0.039f)},
				{FVector2f(0.72f,0),FLinearColor(0.14f,0.034f,0.018f)},
				{FVector2f(1,0),FLinearColor(0.04f,0.009f,0.005f)}});
			Gradient(81,18,W-103,H-42, {
				{FVector2f(0,0),FLinearColor(0.78f,0.44f,0.23f,0.08f)},
				{FVector2f(0,0.4f),FLinearColor(0.10f,0.03f,0.01f,0.f)},
				{FVector2f(0,1),FLinearColor(0.015f,0.005f,0.003f,0.32f)}},false);
			Line({{84,19},{W-25,19},{W-25,H-31}},FLinearColor(0.43f,0.20f,0.09f,0.75f),1.5f);
			Line({{86,H-31},{W-25,H-31}},FLinearColor(0.015f,0.004f,0.002f),3.f);
			Frame(97,41,W-133,H-89,FLinearColor(0.03f,0.008f,0.003f),2.f);
			Frame(101,45,W-137,H-93,FLinearColor(0.41f,0.18f,0.055f,0.7f),1.f);
			Line({{77,19},{77,H-26}},FLinearColor(0.015f,0.006f,0.003f),2.f);
			Line({{80,19},{80,H-26}},FLinearColor(0.35f,0.17f,0.075f,0.6f));
			for(float Y : {100.f, 190.f, 590.f, 680.f})
			{
				Rect(24,Y+3,49,10,FLinearColor(0.025f,0.006f,0.003f,0.8f));
				Gradient(23,Y,49,9, {{FVector2f(0,0),FLinearColor(0.37f,0.17f,0.07f)},{FVector2f(0,0.3f),FLinearColor(0.25f,0.085f,0.035f)},{FVector2f(0,1),FLinearColor(0.075f,0.018f,0.01f)}},false);
				Line({{24,Y},{70,Y}},FableBookStyle::Gold);
			}
			Frame(99,43,W-137,H-93,FableBookStyle::Gold,2.f);
			Frame(106,50,W-151,H-107,FLinearColor(0.51f,0.30f,0.10f),1.f);
			for (float X : {113.f,W-52.f}) for(float Y : {57.f,H-64.f})
			{
				const float DX=X<200 ? 1.f:-1.f, DY=Y<200 ? 1.f:-1.f;
				Line({{X,Y+42*DY},{X,Y},{X+42*DX,Y}},FableBookStyle::Gold,3.f);
				Line({{X+5*DX,Y+32*DY},{X+17*DX,Y+17*DY},{X+32*DX,Y+5*DY}},FableBookStyle::Gold,1.3f);
				Line({{X+10*DX,Y+10*DY},{X+21*DX,Y+10*DY},{X+21*DX,Y+21*DY},{X+10*DX,Y+21*DY},{X+10*DX,Y+10*DY}},FableBookStyle::Gold);
			}
		}
		// Repeatable tiny fibers/grain, never competing with the typography.
		++Layer;
		FRandomStream Grain(1837);
		for (int32 I=0; I<(bOpen?1500:1800); ++I)
		{
			float X=Grain.FRandRange(bOpen?30.f:85.f,W-32.f), Y=Grain.FRandRange(28.f,H-40.f);
			Rect(X,Y,Grain.FRandRange(0.5f,bOpen?2.5f:1.8f),0.7f,bOpen?FLinearColor(0.32f,0.20f,0.085f,0.045f):FLinearColor(0.64f,0.32f,0.14f,0.055f));
		}
		// Silk marker with a forked end made from thin strips.
		++Layer;
		const float RibbonX=W*(bOpen?0.88f:0.80f);
		Rect(RibbonX+3,14,29,106,FLinearColor(0.04f,0.01f,0.005f,0.15f));
		Rect(RibbonX,8,28,91,FLinearColor(0.27f,0.025f,0.019f));
		for(int32 X=0;X<28;++X)
			Rect(RibbonX+X,99,1,17.f*FMath::Abs(X-13.5f)/13.5f,FLinearColor(0.27f,0.025f,0.019f));
		Line({{RibbonX+3,9},{RibbonX+3,103}},FLinearColor(0.60f,0.29f,0.10f,0.55f));
		Line({{RibbonX+24,9},{RibbonX+24,103}},FLinearColor(0.60f,0.29f,0.10f,0.55f));
		return Layer;
	}
};

UFableBookSurface::UFableBookSurface(const FObjectInitializer& ObjectInitializer) : Super(ObjectInitializer)
{
	SetVisibility(ESlateVisibility::HitTestInvisible);
}
void UFableBookSurface::SetOpenBook(bool bOpen)
{
	bOpenBook=bOpen;
	if(BookSurface.IsValid()) { BookSurface->bOpen=bOpen; BookSurface->Invalidate(EInvalidateWidgetReason::Layout | EInvalidateWidgetReason::Paint); }
}
void UFableBookSurface::SynchronizeProperties() { Super::SynchronizeProperties(); SetOpenBook(bOpenBook); }
void UFableBookSurface::ReleaseSlateResources(bool bReleaseChildren) { Super::ReleaseSlateResources(bReleaseChildren); BookSurface.Reset(); }
TSharedRef<SWidget> UFableBookSurface::RebuildWidget() { SAssignNew(BookSurface,SFableBookSurface); BookSurface->bOpen=bOpenBook; return BookSurface.ToSharedRef(); }
