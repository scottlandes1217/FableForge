using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

public class ReplicateImageService : MonoBehaviour
{
    [SerializeField] private string replicateApiKey;
    [SerializeField] private string replicateModelName = "black-forest-labs/flux-2-pro";
    [SerializeField] private string negativePrompt = "blurry, low quality, watermark, text, frame, background";
    [SerializeField] private int pollAttempts = 60;
    [SerializeField] private float pollDelaySeconds = 2f;

    private const string ReplicateBaseUrl = "https://api.replicate.com/v1";
    private string cachedVersion;

    public void GenerateImage(string prompt, Action<Texture2D, string> onComplete)
    {
        StartCoroutine(GenerateImageRoutine(prompt, onComplete));
    }

    private IEnumerator GenerateImageRoutine(string prompt, Action<Texture2D, string> onComplete)
    {
        if (string.IsNullOrWhiteSpace(replicateApiKey))
        {
            onComplete?.Invoke(null, "Replicate API key is missing.");
            yield break;
        }

        string versionError = null;
        string version = null;
        yield return GetModelVersion(result => version = result, error => versionError = error);
        if (!string.IsNullOrEmpty(versionError))
        {
            onComplete?.Invoke(null, versionError);
            yield break;
        }

        string predictionId = null;
        string predictionError = null;
        yield return CreatePrediction(version, prompt, result => predictionId = result, error => predictionError = error);
        if (!string.IsNullOrEmpty(predictionError))
        {
            onComplete?.Invoke(null, predictionError);
            yield break;
        }

        string outputUrl = null;
        string pollError = null;
        yield return PollPrediction(predictionId, result => outputUrl = result, error => pollError = error);
        if (!string.IsNullOrEmpty(pollError))
        {
            onComplete?.Invoke(null, pollError);
            yield break;
        }

        if (string.IsNullOrEmpty(outputUrl))
        {
            onComplete?.Invoke(null, "Prediction returned no output image.");
            yield break;
        }

        using (var textureRequest = UnityWebRequest.Get(outputUrl))
        {
            yield return textureRequest.SendWebRequest();
            if (textureRequest.result != UnityWebRequest.Result.Success)
            {
                onComplete?.Invoke(null, $"Failed to download image: {textureRequest.error}");
                yield break;
            }

            var bytes = textureRequest.downloadHandler.data;
            var texture = new Texture2D(2, 2, TextureFormat.RGBA32, false);
            if (!texture.LoadImage(bytes))
            {
                onComplete?.Invoke(null, "Failed to decode image data.");
                yield break;
            }

            onComplete?.Invoke(texture, null);
        }
    }

    private IEnumerator GetModelVersion(Action<string> onSuccess, Action<string> onError)
    {
        if (!string.IsNullOrEmpty(cachedVersion))
        {
            onSuccess?.Invoke(cachedVersion);
            yield break;
        }

        var url = $"{ReplicateBaseUrl}/models/{replicateModelName}";
        using (var request = UnityWebRequest.Get(url))
        {
            request.SetRequestHeader("Authorization", $"Token {replicateApiKey}");
            yield return request.SendWebRequest();

            if (request.result != UnityWebRequest.Result.Success)
            {
                onError?.Invoke($"Failed to fetch model version: {request.error}");
                yield break;
            }

            var parsed = MiniJson.Deserialize(request.downloadHandler.text) as Dictionary<string, object>;
            if (parsed == null || !parsed.TryGetValue("latest_version", out var latest))
            {
                onError?.Invoke("Model version response did not include latest_version.");
                yield break;
            }

            string version = null;
            if (latest is string latestString)
            {
                version = latestString;
            }
            else if (latest is Dictionary<string, object> latestDict && latestDict.TryGetValue("id", out var idObj))
            {
                version = idObj as string;
            }

            if (string.IsNullOrEmpty(version))
            {
                onError?.Invoke("Unable to parse model version.");
                yield break;
            }

            cachedVersion = version;
            onSuccess?.Invoke(version);
        }
    }

    private IEnumerator CreatePrediction(string version, string prompt, Action<string> onSuccess, Action<string> onError)
    {
        var inputParams = new Dictionary<string, object>
        {
            { "prompt", prompt },
            { "output_format", "png" },
            { "output_quality", 100 }
        };

        if (!string.IsNullOrWhiteSpace(negativePrompt))
        {
            inputParams["negative_prompt"] = negativePrompt;
        }

        var body = new Dictionary<string, object>
        {
            { "version", version },
            { "input", inputParams }
        };

        var json = MiniJson.Serialize(body);
        var url = $"{ReplicateBaseUrl}/predictions";

        using (var request = new UnityWebRequest(url, "POST"))
        {
            var payload = Encoding.UTF8.GetBytes(json);
            request.uploadHandler = new UploadHandlerRaw(payload);
            request.downloadHandler = new DownloadHandlerBuffer();
            request.SetRequestHeader("Authorization", $"Token {replicateApiKey}");
            request.SetRequestHeader("Content-Type", "application/json");

            yield return request.SendWebRequest();

            if (request.result != UnityWebRequest.Result.Success)
            {
                onError?.Invoke($"Failed to create prediction: {request.error}");
                yield break;
            }

            var parsed = MiniJson.Deserialize(request.downloadHandler.text) as Dictionary<string, object>;
            if (parsed == null || !parsed.TryGetValue("id", out var idObj))
            {
                onError?.Invoke("Prediction response did not include id.");
                yield break;
            }

            var id = idObj as string;
            if (string.IsNullOrEmpty(id))
            {
                onError?.Invoke("Prediction id was empty.");
                yield break;
            }

            onSuccess?.Invoke(id);
        }
    }

    private IEnumerator PollPrediction(string predictionId, Action<string> onSuccess, Action<string> onError)
    {
        var url = $"{ReplicateBaseUrl}/predictions/{predictionId}";
        for (var attempt = 0; attempt < pollAttempts; attempt++)
        {
            using (var request = UnityWebRequest.Get(url))
            {
                request.SetRequestHeader("Authorization", $"Token {replicateApiKey}");
                yield return request.SendWebRequest();

                if (request.result != UnityWebRequest.Result.Success)
                {
                    onError?.Invoke($"Failed to poll prediction: {request.error}");
                    yield break;
                }

                var parsed = MiniJson.Deserialize(request.downloadHandler.text) as Dictionary<string, object>;
                if (parsed == null || !parsed.TryGetValue("status", out var statusObj))
                {
                    onError?.Invoke("Prediction status response was invalid.");
                    yield break;
                }

                var status = statusObj as string;
                if (status == "succeeded")
                {
                    if (parsed.TryGetValue("output", out var outputObj))
                    {
                        if (outputObj is string outputString)
                        {
                            onSuccess?.Invoke(outputString);
                            yield break;
                        }

                        var outputs = outputObj as List<object>;
                        if (outputs != null && outputs.Count > 0)
                        {
                            onSuccess?.Invoke(outputs[0] as string);
                            yield break;
                        }
                    }

                    onError?.Invoke("Prediction succeeded but no output was returned.");
                    yield break;
                }

                if (status == "failed" || status == "canceled")
                {
                    onError?.Invoke($"Prediction {status}.");
                    yield break;
                }
            }

            yield return new WaitForSeconds(pollDelaySeconds);
        }

        onError?.Invoke("Prediction timed out.");
    }
}
