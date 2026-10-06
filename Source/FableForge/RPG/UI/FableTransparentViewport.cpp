#include "RPG/UI/FableTransparentViewport.h"
#include "Widgets/SViewport.h"
#include "Layout/Clipping.h"
#include "Rendering/DrawElements.h"

namespace
{
// Keep UViewport's native preview scene/client alive and authoritative. Only its
// Slate paint step changes; Spawn, view transforms, lights and world APIs still
// operate on the original UViewport implementation.
class SFableAlphaViewport : public SViewport
{
public:
 SLATE_BEGIN_ARGS(SFableAlphaViewport) : _ResolutionScale(1.f), _CircularMask(false) {}
  SLATE_ARGUMENT(TSharedPtr<SViewport>, NativeViewport)
  SLATE_ARGUMENT(float, ResolutionScale)
  SLATE_ARGUMENT(bool, CircularMask)
 SLATE_END_ARGS()

 void Construct(const FArguments& Args)
 {
  NativeViewport=Args._NativeViewport;
  ResolutionScale=Args._ResolutionScale;
  bCircularMask=Args._CircularMask;
  // Keep the native viewport in the Slate parent chain. FSceneViewport's
  // OnDrawViewport refuses to resize/create its render target unless
  // FindWidgetWindow(native viewport) resolves a real window.
  // Our OnPaint deliberately bypasses painting this child: its default paint
  // forces opaque blending, but its parent/window relationship remains valid.
  SViewport::Construct(SViewport::FArguments()
   .EnableBlending(true).IgnoreTextureAlpha(false).PreMultipliedAlpha(false)
   [NativeViewport.ToSharedRef()]);
  SetViewportInterface(NativeViewport->GetViewportInterface().Pin().ToSharedRef());
 }

 virtual void Tick(const FGeometry& Geometry,double CurrentTime,float DeltaTime) override
 {
  // The native viewport is attached but not painted (it forces NoBlending), so
  // it must still update FSceneViewport geometry, render requests and its world.
  NativeViewport->Tick(RenderGeometry(Geometry),CurrentTime,DeltaTime);
 }

 virtual int32 OnPaint(const FPaintArgs& Args,const FGeometry& Geometry,const FSlateRect& CullingRect,
  FSlateWindowElementList& Elements,int32 Layer,const FWidgetStyle& Style,bool ParentEnabled) const override
 {
  const TSharedPtr<ISlateViewport> Interface=ViewportInterface.Pin();
  if (!Interface.IsValid()) return Layer;
  // Render to a larger target, then let Slate filter it into the original HUD
  // rectangle. A ScaleBox alone cannot do this: its draw size still renders at
  // the small on-screen size. Other book previews retain their default scale.
  Interface->OnDrawViewport(RenderGeometry(Geometry),CullingRect,Elements,Layer,Style,ParentEnabled);
  const FSlateShaderResource* Texture=Interface->GetViewportRenderTargetTexture();
  if (Texture && !Texture->Debug_IsDestroyed())
  {
   // UE's scene alpha is transmittance: empty pixels=1, opaque surfaces=0.
   // Slate inversion produces coverage. Tonemapped scene RGB is not
   // premultiplied by that coverage: straight alpha must suppress background
   // RGB (including exposure/bloom) wherever the scene is transparent.
   const ESlateDrawEffect Effects=ESlateDrawEffect::InvertAlpha;
   const FLinearColor Tint=Style.GetColorAndOpacityTint();
   const FPaintGeometry PaintGeometry=Geometry.ToPaintGeometry();
   if (!bCircularMask)
   {
    FSlateDrawElement::MakeViewport(Elements,Layer,PaintGeometry,Interface,Effects,Tint);
   }
   else
   {
    // Slate has no native circle clip. Draw the same viewport through a set of
    // conservative horizontal clips; using the furthest edge of each strip
    // keeps every emitted pixel inside the inscribed circle.
    constexpr int32 StripCount=64;
    const FVector2f AbsolutePosition=FVector2f(Geometry.GetAbsolutePosition());
    const FVector2f AbsoluteSize=FVector2f(Geometry.GetAbsoluteSize());
    const float Radius=0.5f*FMath::Min(AbsoluteSize.X,AbsoluteSize.Y);
    const FVector2f Center=AbsolutePosition+0.5f*AbsoluteSize;
    const float StripHeight=AbsoluteSize.Y/static_cast<float>(StripCount);

    for (int32 StripIndex=0;StripIndex<StripCount;++StripIndex)
    {
     const float Top=AbsolutePosition.Y+StripHeight*static_cast<float>(StripIndex);
     const float Bottom=Top+StripHeight;
     const float MaxDistanceY=FMath::Max(FMath::Abs(Top-Center.Y),FMath::Abs(Bottom-Center.Y));
     const float HalfWidth=FMath::Sqrt(FMath::Max(0.f,Radius*Radius-MaxDistanceY*MaxDistanceY));
     if (HalfWidth<=0.f) continue;

     Elements.PushClip(FSlateClippingZone(FSlateRect(Center.X-HalfWidth,Top,Center.X+HalfWidth,Bottom)));
     FSlateDrawElement::MakeViewport(Elements,Layer,PaintGeometry,Interface,Effects,Tint);
     Elements.PopClip();
    }
   }
  }
  // A not-yet-rendered preview stays empty instead of flashing a black box.
  return Layer+1;
 }
private:
 FGeometry RenderGeometry(const FGeometry& Geometry) const
 {
  return Geometry.MakeChild(Geometry.GetLocalSize()*ResolutionScale, FSlateLayoutTransform());
 }
 TSharedPtr<SViewport> NativeViewport;
 float ResolutionScale=1.f;
 bool bCircularMask=false;
};
}

TSharedRef<SWidget> UFableTransparentViewport::RebuildWidget()
{
 const TSharedRef<SWidget> Native=Super::RebuildWidget();
 if (IsDesignTime()) return Native;
 Compositor=SNew(SFableAlphaViewport)
  .NativeViewport(StaticCastSharedRef<SViewport>(Native))
  .ResolutionScale(ResolutionScale)
  .CircularMask(bCircularMask);
 return Compositor.ToSharedRef();
}

void UFableTransparentViewport::SynchronizeProperties()
{
 SetBackgroundColor(FLinearColor::Black);
 Super::SynchronizeProperties();
}

void UFableTransparentViewport::ReleaseSlateResources(bool bReleaseChildren)
{
 Compositor.Reset();
 Super::ReleaseSlateResources(bReleaseChildren);
}
