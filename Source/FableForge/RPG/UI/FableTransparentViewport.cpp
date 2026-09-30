#include "RPG/UI/FableTransparentViewport.h"
#include "Widgets/SViewport.h"
#include "Rendering/DrawElements.h"

namespace
{
// Keep UViewport's native preview scene/client alive and authoritative. Only its
// Slate paint step changes; Spawn, view transforms, lights and world APIs still
// operate on the original UViewport implementation.
class SFableAlphaViewport : public SViewport
{
public:
 SLATE_BEGIN_ARGS(SFableAlphaViewport) : _ResolutionScale(1.f) {}
  SLATE_ARGUMENT(TSharedPtr<SViewport>, NativeViewport)
  SLATE_ARGUMENT(float, ResolutionScale)
 SLATE_END_ARGS()

 void Construct(const FArguments& Args)
 {
  NativeViewport=Args._NativeViewport;
  ResolutionScale=Args._ResolutionScale;
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
   FSlateDrawElement::MakeViewport(Elements,Layer,Geometry.ToPaintGeometry(),Interface,Effects,Style.GetColorAndOpacityTint());
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
};
}

TSharedRef<SWidget> UFableTransparentViewport::RebuildWidget()
{
 const TSharedRef<SWidget> Native=Super::RebuildWidget();
 if (IsDesignTime()) return Native;
 Compositor=SNew(SFableAlphaViewport).NativeViewport(StaticCastSharedRef<SViewport>(Native)).ResolutionScale(ResolutionScale);
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
