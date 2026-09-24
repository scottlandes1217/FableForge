#include "RPG/UI/FableItemIconLibrary.h"
#include "Engine/Texture2D.h"
#include "ImageUtils.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#include "UObject/StrongObjectPtr.h"
#include <initializer_list>

namespace
{
	// Draw at twice the delivery resolution. The downsample keeps diagonal silhouettes
	// readable in small inventory cells without shipping platform-specific font glyphs.
	struct FEmblem
	{
		static constexpr int32 Size = 256;
		TArray<FColor> Pixels;
		FEmblem() { Pixels.Init(FColor::Transparent, Size * Size); }
		void Polygon(std::initializer_list<FVector2D> Vertices, FColor Color)
		{
			TArray<FVector2D> Points;
			for (FVector2D Point : Vertices) { Points.Add(Point * 2.56); }
			for (int32 Y = 0; Y < Size; ++Y)
			for (int32 X = 0; X < Size; ++X)
			{
				bool Inside = false;
				for (int32 I = 0, J = Points.Num() - 1; I < Points.Num(); J = I++)
				{
					const FVector2D A = Points[I], B = Points[J];
					if (((A.Y > Y + .5) != (B.Y > Y + .5)) &&
						(X + .5 < (B.X - A.X) * (Y + .5 - A.Y) / (B.Y - A.Y) + A.X)) { Inside = !Inside; }
				}
				if (Inside) { Pixels[Y * Size + X] = Color; }
			}
		}
		void Circle(float CX, float CY, float R, FColor Color)
		{
			for (int32 Y = 0; Y < Size; ++Y)
			for (int32 X = 0; X < Size; ++X)
			{
				if (FMath::Square((X + .5f) / 2.56f - CX) + FMath::Square((Y + .5f) / 2.56f - CY) <= R * R)
				{ Pixels[Y * Size + X] = Color; }
			}
		}
	};
	const FColor Gold(208, 170, 94), Light(239, 225, 185), Steel(155, 191, 206), Dark(44, 58, 67), Leather(134, 88, 57);
}

UTexture2D* FableItemIcons::Get(const FString& ItemId)
{
	if (ItemId.IsEmpty()) { return nullptr; }
	FString Key = ItemId.ToLower();
	Key.RemoveFromStart(TEXT("skill:"));
	// One texture per identity, retained across widget destruction and level travel.
	static TMap<FString, TStrongObjectPtr<UTexture2D>> Cache;
	if (const TStrongObjectPtr<UTexture2D>* Found = Cache.Find(Key)) { return Found->Get(); }
	// Offline renders of the actual item meshes take priority over generic emblems.
	// Content/Slate is staged by Unreal for packaged UI, without an editor dependency.
	const FString IconPath = FPaths::ProjectContentDir() / TEXT("Slate/ItemIcons") / (Key + TEXT(".png"));
	if (!Key.Contains(TEXT("/")) && !Key.Contains(TEXT("\\")) && IFileManager::Get().FileExists(*IconPath))
	{
		if (UTexture2D* Rendered = FImageUtils::ImportFileAsTexture2D(IconPath))
		{
			Rendered->NeverStream = true;
			Rendered->Filter = TF_Bilinear;
			Rendered->LODGroup = TEXTUREGROUP_UI;
			Cache.Add(Key, TStrongObjectPtr<UTexture2D>(Rendered));
			return Rendered;
		}
	}
	FEmblem Art;
	if (Key.Contains(TEXT("potion")) || Key == TEXT("honey"))
	{
		Art.Polygon({{39,20},{61,20},{61,38},{73,52},{76,72},{67,84},{33,84},{24,72},{27,52},{39,38}}, Steel);
		Art.Polygon({{32,54},{68,54},{70,70},{62,78},{38,78},{30,70}}, Key.Contains(TEXT("mana")) ? FColor(69,133,226) : Key == TEXT("honey") ? Gold : FColor(188,63,77));
		Art.Polygon({{38,15},{62,15},{62,25},{38,25}}, Leather);
		Art.Polygon({{36,49},{42,43},{42,67},{36,70}}, Light);
	}
	else if (Key.Contains(TEXT("sword")) || Key.Contains(TEXT("attack")) || Key.Contains(TEXT("strike")))
	{
		Art.Polygon({{34,64},{72,17},{86,12},{84,29},{43,70}}, Steel);
		Art.Polygon({{40,64},{80,18},{77,30},{46,66}}, Light);
		Art.Polygon({{22,57},{28,51},{52,75},{46,81}}, Gold);
		Art.Polygon({{17,80},{31,65},{38,72},{24,88}}, Leather);
		Art.Circle(20,84,6,Gold);
	}
	else if (Key.Contains(TEXT("staff")))
	{
		Art.Polygon({{26,85},{33,89},{68,30},{61,26}}, Leather);
		Art.Polygon({{58,15},{73,12},{82,27},{68,39},{56,29}}, Gold);
		Art.Polygon({{62,19},{71,17},{76,27},{68,33},{61,27}}, FColor(105,175,217));
	}
	else if (Key == TEXT("wood"))
	{
		Art.Polygon({{20,59},{63,22},{79,30},{86,47},{41,84}}, Leather);
		Art.Polygon({{26,57},{65,27},{72,31},{33,66}}, Gold);
		Art.Circle(32,72,15,Gold); Art.Circle(32,72,10,Leather); Art.Circle(32,72,5,Gold);
	}
	else if (Key == TEXT("stone") || Key.Contains(TEXT("ore")) || Key.Contains(TEXT("earth")) || Key.Contains(TEXT("stone")))
	{
		Art.Polygon({{17,64},{30,35},{57,25},{78,40},{87,70},{65,84},{29,80}}, Dark);
		Art.Polygon({{19,63},{31,37},{56,28},{62,56},{44,71}}, Steel);
		Art.Polygon({{56,28},{76,42},{84,69},{62,56}}, Light);
		if (Key.Contains(TEXT("ore"))) { Art.Polygon({{38,45},{48,39},{56,49},{47,62}}, Gold); Art.Circle(70,70,5,Gold); }
	}
	else if (Key == TEXT("berries"))
	{
		Art.Polygon({{48,40},{36,19},{54,25},{64,16},{63,38}}, FColor(102,151,93));
		for (FVector2D P : {FVector2D(35,48),FVector2D(59,47),FVector2D(47,65),FVector2D(68,65),FVector2D(32,69)})
		{ Art.Circle(P.X,P.Y,13,FColor(134,65,118)); Art.Circle(P.X-4,P.Y-4,3,Light); }
	}
	else if (Key == TEXT("meat"))
	{
		Art.Polygon({{57,61},{77,78},{83,73},{64,54}}, Light); Art.Circle(80,81,7,Light); Art.Circle(87,73,7,Light);
		Art.Circle(44,43,25,Leather); Art.Circle(42,41,21,FColor(183,91,77)); Art.Circle(36,34,10,FColor(217,131,104));
	}
	else if (Key.Contains(TEXT("chest")))
	{
		Art.Polygon({{34,22},{44,28},{56,28},{66,22},{84,42},{72,54},{64,46},{66,82},{34,82},{36,46},{28,54},{16,42}}, Leather);
		Art.Polygon({{44,28},{50,37},{56,28},{56,75},{44,75}}, Gold);
		Art.Polygon({{34,65},{66,65},{66,72},{34,72}}, Dark);
	}
	else if (Key.Contains(TEXT("legs")))
	{
		Art.Polygon({{30,20},{70,20},{70,47},{64,85},{51,85},{49,48},{44,85},{30,85},{26,47}}, Leather);
		Art.Polygon({{30,20},{70,20},{70,29},{30,29}}, Gold);
	}
	else if (Key.Contains(TEXT("feet")) || Key.Contains(TEXT("boot")))
	{
		Art.Polygon({{26,22},{46,22},{45,62},{57,73},{55,84},{19,84},{19,68},{25,59}}, Leather);
		Art.Polygon({{56,18},{76,18},{75,58},{87,69},{85,80},{57,80},{57,64}}, Gold);
		Art.Polygon({{19,78},{55,78},{55,85},{19,85}}, Dark);
	}
	else if (Key.Contains(TEXT("arms")))
	{
		Art.Polygon({{26,19},{48,25},{38,83},{17,76}}, Leather);
		Art.Polygon({{57,25},{79,19},{88,76},{67,83}}, Leather);
		Art.Polygon({{23,34},{46,40},{43,48},{21,42}}, Gold);
		Art.Polygon({{60,40},{82,34},{84,42},{62,48}}, Gold);
	}
	else if (Key.Contains(TEXT("fire")) || Key.Contains(TEXT("blaz")) || Key.Contains(TEXT("burn")) || Key.Contains(TEXT("flame")) || Key.Contains(TEXT("ignite")) || Key.Contains(TEXT("deton")) || Key == TEXT("explosion") || Key == TEXT("backdraft"))
	{
		Art.Polygon({{49,12},{64,38},{72,28},{83,59},{77,77},{58,88},{35,82},{20,63},{30,40},{37,53}}, FColor(215,102,54));
		Art.Polygon({{52,40},{66,62},{61,79},{44,79},{36,65}}, Gold);
	}
	else if (Key.Contains(TEXT("heal")) || Key.Contains(TEXT("restor")))
	{
		Art.Circle(50,50,34,FColor(48,105,92));
		Art.Polygon({{43,25},{57,25},{57,43},{75,43},{75,57},{57,57},{57,75},{43,75},{43,57},{25,57},{25,43},{43,43}}, Light);
	}
	else if (Key.Contains(TEXT("spark")) || Key.Contains(TEXT("lightning")) || Key.Contains(TEXT("jolt")) || Key.Contains(TEXT("conductive")) || Key.Contains(TEXT("magnetic")))
	{
		Art.Polygon({{53,12},{77,12},{56,43},{74,43},{30,90},{42,57},{24,57}}, Gold);
	}
	else if (Key.Contains(TEXT("frost")) || Key.Contains(TEXT("glacial")) || Key.Contains(TEXT("shatter")))
	{
		Art.Polygon({{51,12},{72,40},{52,85},{29,59}}, Steel);
		Art.Polygon({{51,12},{52,85},{44,47}}, Light);
		Art.Polygon({{20,31},{34,39},{28,61},{14,49}}, Steel);
		Art.Polygon({{77,53},{88,64},{73,86},{68,72}}, Light);
	}
	else if (Key.Contains(TEXT("gust")) || Key.Contains(TEXT("wind")) || Key.Contains(TEXT("sky")))
	{
		Art.Polygon({{17,34},{63,34},{70,27},{65,20},{57,23},{54,17},{68,13},{80,26},{72,41},{17,41}}, Steel);
		Art.Polygon({{26,49},{83,49},{83,56},{26,56}}, Light);
		Art.Polygon({{15,64},{61,64},{71,74},{66,85},{56,88},{53,81},{61,79},{62,74},{15,71}}, Steel);
	}
	else if (Key.Contains(TEXT("blink")) || Key.Contains(TEXT("dodge")) || Key.Contains(TEXT("dash")))
	{
		Art.Polygon({{22,20},{36,20},{65,50},{36,80},{22,80},{51,50}}, Gold);
		Art.Polygon({{49,20},{63,20},{92,50},{63,80},{49,80},{78,50}}, Light);
	}
	else
	{
		// Unrecognized abilities/items keep a neutral rune; authored art always wins.
		Art.Polygon({{50,15},{79,50},{50,85},{21,50}}, Gold);
		Art.Polygon({{50,25},{69,50},{50,75},{31,50}}, Dark);
		Art.Polygon({{50,34},{60,50},{50,66},{40,50}}, Steel);
	}
	UTexture2D* Texture = UTexture2D::CreateTransient(128, 128, PF_B8G8R8A8);
	if (!Texture) { return nullptr; }
	Texture->SRGB = true;
	Texture->NeverStream = true;
	Texture->Filter = TF_Bilinear;
	Texture->LODGroup = TEXTUREGROUP_UI;
	FColor* Dest = static_cast<FColor*>(Texture->GetPlatformData()->Mips[0].BulkData.Lock(LOCK_READ_WRITE));
	for (int32 Y = 0; Y < 128; ++Y)
	for (int32 X = 0; X < 128; ++X)
	{
		int32 R=0,G=0,B=0,A=0;
		for (int32 DY=0;DY<2;++DY) for (int32 DX=0;DX<2;++DX)
		{
			const FColor C=Art.Pixels[(Y*2+DY)*256+X*2+DX];
			R+=C.R*C.A; G+=C.G*C.A; B+=C.B*C.A; A+=C.A;
		}
		Dest[Y*128+X] = A ? FColor(R/A,G/A,B/A,A/4) : FColor::Transparent;
	}
	Texture->GetPlatformData()->Mips[0].BulkData.Unlock();
	Texture->UpdateResource();
	Cache.Add(Key,TStrongObjectPtr<UTexture2D>(Texture));
	return Texture;
}
