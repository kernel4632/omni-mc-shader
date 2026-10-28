/* 体积雾的云影：把世界坐标投到云影贴图，并用四次双线性采样合成十六像素三次模糊；由 `fog/volume.slang` 内联引入，不单独生成 GLSL 或探针。
可复制示例：`float shadow = ogxFogCloudShadow(worldPos, media, cloudShadowTex, true);`
设计原因与取舍：子文件只服务所属主模块，函数顺序与主文件引用顺序一致。
调用位置：由所属主文件内联引入，不单独生成 GLSL 或探针。
*/

// 云影贴图的三次采样：取红通道，与云影写入端同一套模糊。
// 四次双线性采样合成十六像素三次模糊，纹理读取次数只有逐像素方案的四分之一。
float ogxFogCloudBicubic(Sampler2D source, float2 coord, float2 texSize)
{
    float2 texel = 1.0 / texSize; // 一个纹素的大小。
    coord = coord * texSize - 0.5; // 换成以像素中心为原点。
    float2 p = floor(coord); // 整数像素。
    float2 f = coord - p; // 小数偏移。
    float2 ff = f * f; // 偏移平方。
    float4 w0; // 前两个权重。
    float4 w1; // 后两个权重。
    w0.xz = 1.0 - f; w0.xz *= w0.xz * w0.xz; // 第一个权重。
    w1.yw = ff * f; // 第四个权重。
    w1.xz = 3.0 * w1.yw + 4.0 - 6.0 * ff; // 第三个权重。
    w0.yw = 6.0 - w1.xz - w1.yw - w0.xz; // 第二个权重。
    float4 s = w0 + w1; // 每对权重和。
    float4 c = p.xxyy + float2(-0.5, 1.5).xyxy + w1 / s; // 合并采样位置。
    c *= texel.xxyy; // 换回零到一坐标。
    float2 m = s.xz / (s.xz + s.yw); // 两次采样之间的混合比例。
    return lerp(lerp(source.SampleLevel(c.yw, 0.0).x, source.SampleLevel(c.xw, 0.0).x, m.x),
                lerp(source.SampleLevel(c.yz, 0.0).x, source.SampleLevel(c.xz, 0.0).x, m.x), m.y); // 四次采样合成模糊。
}

// 云影贴图取值：把世界坐标投到云影贴图，采样后按天气在晴天与雨天两档之间混合。
float ogxFogCloudShadow(float3 worldPos, OgxFogMedia media, Sampler2D cloudShadowTex, bool fadeByAngle)
{
    float2 coord = worldPos.xz - media.light_vector.xz * ((worldPos.y + media.camera_position.y) / media.light_vector.y); // 沿光方向投到云影贴图平面。
    coord = coord * (1.0 / media.cloud_shadow_range) + 0.5; // 换成零到一的贴图坐标。
    float cloudShadow = 1.0 - media.wetness; // 雨天默认的云影底值。
    if (ogxEqual(ogxSaturate(coord), coord)) // 只有落在贴图范围内才采样。
    {
        float shadowTexSize = floor(min(media.cloud_shadow_screen.y * 0.45, media.cloud_shadow_tex_size)); // 云影贴图实际边长。
        float2 shadowTexel = media.cloud_shadow_screen - coord * shadowTexSize; // 贴图贴在画面右上角，坐标要翻转。
        float2 fade = ogxSaturate(5.9 - abs(coord - 0.5) * 12.0); // 贴图边缘淡出，避免硬边界。
        cloudShadow = lerp(cloudShadow, ogxFogCloudBicubic(cloudShadowTex, shadowTexel * media.cloud_shadow_texel, media.cloud_shadow_screen), fade.x * fade.y); // 三次采样并淡出。
    }
    if (fadeByAngle) // 太阳越贴地云影越淡。
    {
        float fadeAngle = smoothstep(0.06, 0.18, abs(media.light_vector.y)); // 光方向越平越淡。
        cloudShadow = lerp(1.0 - media.wetness, cloudShadow, fadeAngle * fadeAngle); // 按淡出权重混合。
    }
    return ((media.rain_shadow - 1.0) * media.wetness + 1.0) * cloudShadow + (media.wetness - media.rain_shadow * media.wetness); // 晴天与雨天两档之间插值。
}

// 暴风浓雾密度，具体实现在子文件。
// --- storm ---
