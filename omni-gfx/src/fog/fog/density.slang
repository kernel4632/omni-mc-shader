/*
雾子文件：默认雾参数、高度密度、噪声雾团、相位、粉末效应与单次步进。
调用位置：由 `fog/fog.slang` 内联，主世界、下界与末地的雾效果共用这里的密度曲线。
可复制示例：`float d = ogxFogDensity(ogxFogDefault(), worldPos);`
设计原因与取舍：密度只依赖位置与参数，天气与光源颜色由调用方乘进来；噪声层数照参考固定。
*/
// 默认低空雾：贴地薄雾，密度适中，云影下会自然变暗。
OgxFog ogxFogDefault()
{
    OgxFog fog; // 先声明再填写字段。
    fog.color = float3(0.55, 0.68, 0.82); // 偏冷的天空色。
    fog.density = 0.18; // 每公里密度，远景能看到空气感。
    fog.heightFalloff = 0.06; // 六十米高度衰减，雾贴在低空。
    fog.baseHeight = 0.0; // 海平面最浓。
    fog.noiseScale = 9.0; // 百米级雾团。
    fog.noiseStrength = 0.75; // 噪声明显但不把雾打碎。
    fog.wind = float3(0.0, 0.0, 0.0); // 风由调用方按时间填写。
    fog.sunStrength = 1.0; // 阳光散射默认全强。
    return fog; // 返回可直接修改的默认值。
}

// 雾密度：高度指数衰减乘三维噪声，得到会流动的雾团。
float ogxFogDensity(OgxFog fog, float3 position)
{
    float height = exp(-max(position.y - fog.baseHeight, 0.0) / max(fog.heightFalloff, 1e-4)); // 高度包络。
    float3 noisePosition = (position + fog.wind) * fog.noiseScale; // 换到雾坐标并叠加风。
    float noise = ogxFbm3(noisePosition, 3); // 三层次雾团。
    return fog.density * height * lerp(1.0, noise * 1.6, ogxSaturate(fog.noiseStrength)); // 噪声只调制密度，不改变高度剖面。
}

// 混合相位：三成后向、七成前向，逆光和顺光都不会过曝。
float ogxFogPhase(float nu)
{
    return ogxMiePhase(-0.4, nu) * 0.3 + ogxMiePhase(0.5, nu) * 0.7; // 与旧雾模块相同的权重。
}

// 粉末效应：薄雾在背光方向略微增亮，模拟多次散射。
float ogxFogPowder(float density, float nu)
{
    float powder = 1.0 - exp(-max(density, 0.0) * 4.0); // 密度越低越明显。
    return lerp(1.0, powder, ogxSaturate(0.5 - 0.5 * nu)); // 只影响背光方向。
}

// 沿视线积分雾：返回预乘散射色与剩余透过率。

// 把雾应用到已经着色的颜色：先乘剩余透过率，再加散射色。

// 按比例淡出一层预乘雾：只缩放散射色，并把透过率朝一插值。
// 为什么不能直接把四个分量一起乘小：透过率被乘小以后，颜色会被一起抹掉，
// 在“远处收敛到天空色、同时淡出雾”的接缝处就会压出一条黑线。
// `amount` 零表示完全不要这层雾，一表示保留原样。
float4 ogxFogFade(float4 fog, float amount)
{
    amount = ogxSaturate(amount); // 比例夹在零到一。
    return float4(fog.rgb * amount, lerp(1.0, fog.a, amount)); // 散射按比例缩放，透过率朝完全透明靠近。
}

// 粉末效应：背光时气溶胶把光往前推，边缘因此更亮，正对时补偿回去。
float ogxLegacyPowder(float absorption, float lightingAbsorption, float VdotL)
{
    return lerp((1.0 - absorption) * (1.0 - lightingAbsorption), 1.0, VdotL * 0.5 + 0.5); // 吸收越强效果越强。
}

// 混合相位：后向与前向两个米氏相位加权，雾的轮廓在逆光时仍有层次。
float ogxLegacyFogPhase(float VdotL)
{
    return ogxMiePhase(-0.4, VdotL) * 0.3 + ogxMiePhase(0.5, VdotL) * 0.7; // 前向占七成。
}

// 多次散射相位：四个衰减档各给一个相位，用来叠出体积雾的多层散射。
// 返回四分量的原因是 GLSL 的数组参数在 Slang 里没有等价写法，四档直接装进一个向量。
float4 ogxMultiScatteringPhases(float VdotL)
{
    return float4(ogxLegacyFogPhase(VdotL), ogxLegacyFogPhase(VdotL * 0.5),
                  ogxLegacyFogPhase(VdotL * 0.25), ogxLegacyFogPhase(VdotL * 0.125)); // 四档角度逐次减半，与旧实现的循环一致。
}

// 雾密度的高度剖面：两层高度之间的空气最浓，离开这段距离按指数下降，夜间更浓。
float ogxFogDensityHeight(float3 fogPos, float heightA, float heightB, float falloff, float timeMidnight)
{
    float maxHeight = max(heightA, heightB); // 两层里较高的。
    float minHeight = min(heightA, heightB); // 两层里较低的。
    float dh = max(fogPos.y - maxHeight, 0.0) + max(minHeight - fogPos.y, 0.0); // 到浓度层的距离。
    dh *= 2.0 / falloff; // 按衰减距离归一化。
    float density = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 指数下降，夜里衰减更慢。
    return density * 0.1; // 乘基础密度。
}

// 噪声雾密度：高度包络乘四层噪声，平方两次让雾团边界清楚。
float ogxFogDensityNoise(float3 fogPos, float3 wind, float heightA, float heightB, float falloff,
    float timeMidnight, Sampler2D noiseTexture)
{
    float dh = abs(fogPos.y - max(heightA, heightB)); // 到浓度层的距离。
    dh *= 1.0 / falloff; // 按衰减距离归一化。
    float envelope = exp2(-dh * (1.0 - timeMidnight * 0.5)); // 高度衰减包络。
    float density = 0.0; // 累积的雾密度。
    fogPos = fogPos * 0.02 + wind; // 缩放坐标并叠加风向。
    for (float alpha = 0.5; alpha >= 0.125; alpha *= 0.5) // 四层不同频率的噪声。
    {
        density += alpha * ogxFogNoise(fogPos, noiseTexture); // 按权重累加。
        fogPos = (fogPos + wind) * 3.5; // 抬高频率并再叠一次风。
    }
    density *= envelope; // 乘高度衰减。
    density = density * density; // 平方让雾团更实。
    return density * density * 3.0; // 再平方并放大，得到清楚的边界。
}

// 三维噪声与云状分形在通用噪声模块：吸积盘、雾与体积云共用同一份查表公式。

// 下界雾的单格密度：世界坐标折成三维格子，再查二维噪声图。
float ogxNetherFogDensityAt(float3 pos, Sampler2D noiseTexture)
{
    pos /= 18.0; // 整体缩小，让格子更大。
    pos.xz *= 0.5; // 水平再压一半，雾团更扁。
    float3 p = floor(pos); // 整数格坐标。
    float3 f = fract(pos); // 格内小数偏移。
    f = f * f * (3.0 - 2.0 * f); // 平滑小数。
    float2 uv = p.xz + f.xz + p.y * float2(0.0, 193.0); // 三维格子映射到二维图，纵轴加大偏移错开层。
    float2 xy = noiseTexture.SampleLevel(uv / 512.0, 0.0).yx; // 读两通道并交换，零号层级与旧实现一致。
    return lerp(xy.r, xy.g, f.y); // 按高度插值。
}

// 下界体积雾的原始密度：羽流、贴地烟与高度包络叠在一起。
// 羽流给竖直烟柱，贴地烟给低处一层，两者取较大者，避免叠加过曝。
float ogxNetherFogCloudVolume(float3 pos, float time, Sampler2D noiseTexture)
{
    float3 samplePos = pos * float3(1.0, 1.0 / 48.0, 1.0); // 竖直拉伸，烟柱显得更高。
    float wind = pow(max(pos.y - 30.0, 0.0) / 15.0, 2.1); // 越高风偏移越大。
    float plumes = noiseTexture.SampleLevel((samplePos.xz + wind) / 256.0, 0.0).b; // 噪声蓝通道当羽流形状。
    float floorPlumes = clamp(0.3 - exp(plumes * -6.0), 0.0, 1.0); // 贴地烟的量。
    plumes *= plumes; // 平方拉开烟与空的差别。
    float erosion = ogxNetherFogDensityAt(samplePos * 400.0 - time * 10.0 - wind * 10.0, noiseTexture) * 0.7 + 0.3; // 随时间的侵蚀。
    float roofToFloor = exp(max(100.0 - pos.y, 0.0) / -15.0); // 从天花板到地面变淡。
    float floorFalloff = pow(exp(max(pos.y - 31.0, 0.0) / -3.0), 2.0); // 离地越高越淡。
    float roofFalloff = exp(max(120.0 - pos.y, 0.0) / -10.0); // 参考实现保留的屋顶包络。
    return max((roofToFloor - plumes * (1.0 - erosion)) * 2.0, clamp((floorFalloff - floorPlumes * 0.5) * erosion, 0.0, 1.0)); // 两种形状取大者。
}
