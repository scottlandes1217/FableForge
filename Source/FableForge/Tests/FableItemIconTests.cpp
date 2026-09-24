#if WITH_DEV_AUTOMATION_TESTS

#include "Misc/AutomationTest.h"
#include "Misc/Crc.h"
#include "Engine/Texture2D.h"
#include "RPG/UI/FableItemIconLibrary.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FFableItemIconCoverageTest,
	"FableForge.UI.ItemIcons.CoverageAndCaching",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FFableItemIconCoverageTest::RunTest(const FString& Parameters)
{
	// All currently shipped item rows have no authored icon. Each fallback must
	// contain visible pixels and be visually distinguishable from the other items.
	const TCHAR* ItemIds[] = {
		TEXT("health_potion"), TEXT("mana_potion"), TEXT("wood"), TEXT("stone"),
		TEXT("iron_ore"), TEXT("meat"), TEXT("honey"), TEXT("berries"),
		TEXT("iron_sword"), TEXT("magic_staff"), TEXT("peasant_chest"),
		TEXT("peasant_legs"), TEXT("peasant_feet"), TEXT("peasant_arms")
	};
	TSet<uint32> ImageHashes;
	TestNull(TEXT("Empty slots have no emblem"), FableItemIcons::Get(TEXT("")));
	for (const TCHAR* ItemId : ItemIds)
	{
		UTexture2D* Texture = FableItemIcons::Get(ItemId);
		if (!TestNotNull(ItemId, Texture)) { continue; }
		TestTrue(TEXT("Repeated lookup reuses texture"), Texture == FableItemIcons::Get(ItemId));
		TestTrue(TEXT("Case normalization reuses texture"), Texture == FableItemIcons::Get(FString(ItemId).ToUpper()));
		TestEqual(TEXT("Icon width"), Texture->GetSizeX(), 128);
		TestEqual(TEXT("Icon height"), Texture->GetSizeY(), 128);
		TestTrue(TEXT("UI icons do not stream"), Texture->NeverStream);
		FTexture2DMipMap& Mip = Texture->GetPlatformData()->Mips[0];
		const FColor* Pixels = static_cast<const FColor*>(Mip.BulkData.LockReadOnly());
		if (TestNotNull(TEXT("Readable generated pixels"), Pixels))
		{
			int32 VisiblePixels = 0;
			for (int32 PixelIndex = 0; PixelIndex < 128 * 128; ++PixelIndex)
			{
				VisiblePixels += Pixels[PixelIndex].A > 0 ? 1 : 0;
			}
			TestTrue(TEXT("Emblem has a readable silhouette"), VisiblePixels > 500);
			TestTrue(TEXT("Emblem preserves transparent padding"), VisiblePixels < 128 * 128);
			ImageHashes.Add(FCrc::MemCrc32(Pixels, 128 * 128 * sizeof(FColor)));
		}
		Mip.BulkData.Unlock();
	}
	TestEqual(TEXT("Every shipped item has distinct art"), ImageHashes.Num(), 14);
	TestTrue(TEXT("Skill prefix normalizes the cache identity"),
		FableItemIcons::Get(TEXT("skill:fireball")) == FableItemIcons::Get(TEXT("fireball")));
	TestNotNull(TEXT("Unknown future items receive a neutral rune"), FableItemIcons::Get(TEXT("unrecognized_item")));
	return true;
}

#endif
