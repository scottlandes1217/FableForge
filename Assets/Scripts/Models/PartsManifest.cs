using System;
using System.Collections.Generic;

[Serializable]
public class PartsManifest
{
    public string rig;
    public Dictionary<string, List<PartsManifestEntry>> categories = new Dictionary<string, List<PartsManifestEntry>>();
}

[Serializable]
public class PartsManifestEntry
{
    public string label;
    public string path;
}
