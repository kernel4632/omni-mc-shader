/*
生成文件：光传播体积模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中按效果分文件夹，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库光传播体积模块：三维彩色间接光的取样、编码与边缘淡出。
调用位置：任何把体素网格里的彩色间接光取回表面的程序；Minecraft 光影由 `shaders/effects/shared/lpv.glsl` 调用。
可复制示例：
    `vec4 texel = ogxLpvDecodeSample(stored, vec2(15.0, 24.0));` 解码存下的色相与亮度。
    `vec3 block = ogxLpvBlockLight(texel);` 取回彩色方块光。
    `float sky = ogxLpvSkyLight(texel);` 取回天光。
设计原因与取舍：
    纹理句柄、帧号奇偶与网格尺寸全部由调用方传入，库只收已经取到的四分量样本，
    因此同一份算式能同时用于 GLSL 330 与 SPIR-V，不绑定任何引擎的三维纹理约定。
    编码沿用“色相照原样存、饱和度与天光取对数”的方案，解码必须与编码逐项对齐，
    否则一进一出之后光色会偏，这也是这对函数放在同一个文件里的原因。
*/
#ifndef OGX_LPV_INCLUDED
#define OGX_LPV_INCLUDED

// 光色与解码都要用颜色换算，直接引入颜色模块，它已经带上数学模块。
#include "/omni-gfx/common/color.glsl"
// 手持光提供方块光表拆包，参考签名的 LPV 雾入口在循环里采样主手与副手光。
#include "/omni-gfx/heldlight.glsl"
// 方块光的亮度系数：存下的颜色取值零到十五，除以十五得到零到一。
const float OGX_LPV_BLOCK_BRIGHTNESS = 0.066666;

// 体积光的亮度曲线：平方放大，让弱光抬起来、强光更快饱和。
// 与解码端的曲线必须一致，改一处就要同步另一处，否则光强会整体漂移。
float ogxLpvCurve(float value) { return value * value; }

// 把归一化坐标换成三维纹理坐标：体积边长由调用方给出。
vec3 ogxLpvUvw(vec3 lpvPos, float side) { return lpvPos / side; }

// 把相机相对位置搬进体积中心：加上相机所在格的小数部分，玩家走动时体积按整格平移。
vec3 ogxLpvPosition(vec3 playerPos, vec3 cameraFract, float halfSide)
{
    return playerPos + cameraFract + halfSide;
}

// 参考签名的体积坐标：玩家相对位置加相机偏移，再平移到体积中心。
// 与上一个函数是同一件事，只是参考参数把半边长写成三轴同一个值，保留独立入口供严格对照。
vec3 ogxLpvPositionExplicit(vec3 playerPos, vec3 cameraOffset, float lpvSize)
{
    return playerPos + cameraOffset + vec3(lpvSize * 0.5); // 与参考实现的 `LpvSize3/2u` 相同。
}

// 解码一个已经取到的体积样本：先按色相还原颜色，再按平方曲线放大亮度并归一到零到一。
// 为什么先当颜色再转 HSV：写入端把亮度压进饱和度通道，读回来必须走同一条逆路径。
// 参数名不用 `sample`：它在 GLSL 4.0 以后是插值限定符，430 的计算程序会直接报语法错误。
vec4 ogxLpvDecodeSample(vec4 texel, vec2 blockSkyRange)
{
    vec3 hsv = ogxRgbToHsv(texel.rgb);
    hsv.z = ogxLpvCurve(hsv.b) * blockSkyRange.x;
    texel.rgb = ogxHsvToRgb(hsv);
    texel.rgb = ogxSaturate(texel.rgb / 15.0);
    return texel;
}

// Eclipse 的 LPV 线性取样入口：按帧号奇偶从两张三维纹理中取一张，再走同一份解码。
// 为什么显式传入两张纹理：参考实现读 texLpv1/texLpv2，库不绑定宿主纹理槽位。
vec4 ogxLpvSampleLinear(vec3 lpvPos, sampler3D lpv1, sampler3D lpv2,
    int frameCounter, float lpvSize, vec2 blockSkyRange)
{
    vec3 texcoord = lpvPos / lpvSize; // 归一化到体积坐标。
    vec4 texel = (frameCounter % 2) == 0
        ? textureLod(lpv1, texcoord, 0.0) : textureLod(lpv2, texcoord, 0.0); // 按帧号二选一。
    return ogxLpvDecodeSample(texel, blockSkyRange); // 解码色相与亮度。
}

// 彩色方块光：亮度系数乘解码后的颜色，供表面照明使用。
vec3 ogxLpvBlockLight(vec4 texel) { return OGX_LPV_BLOCK_BRIGHTNESS * texel.rgb; }

// 天光：先夹到零到一，再平方，暗处变化更柔和。
float ogxLpvSkyLight(vec4 texel)
{
    float skyLight = ogxSaturate(texel.a);
    return skyLight * skyLight;
}

// 写入端的编码：色相照原样，饱和度与天光取对数，压住八位图存不下的动态范围。
vec4 ogxLpvEncode(vec4 value, vec2 blockSkyRange)
{
    vec4 hsvSky = vec4(ogxRgbToHsv(value.rgb), value.a);
    hsvSky.zw = log2(hsvSky.zw + 1.0) / blockSkyRange;
    return vec4(ogxHsvToRgb(hsvSky.xyz), hsvSky.w);
}

// 传播阶段读回上一步结果的解码：与编码严格互逆，指数还原后再减一。
vec4 ogxLpvDecode(vec4 stored, vec2 blockSkyRange)
{
    vec4 hsvSky = vec4(ogxRgbToHsv(stored.rgb), stored.a);
    hsvSky.zw = exp2(hsvSky.zw * blockSkyRange) - 1.0;
    return vec4(ogxHsvToRgb(hsvSky.xyz), hsvSky.w);
}

// 体积边缘淡出：先算到六个面的距离比，三轴相乘后中心满值、边缘归零。
// 为什么要再压一次曲线：直接相乘在角上掉得太快，会看到明显的方形边界。
float ogxLpvRangeFalloff(vec3 lpvPos, float side, float fadeLength)
{
    vec3 cubicRadius = clamp(min((vec3(side) - 1.0 - lpvPos) / fadeLength, lpvPos / fadeLength), vec3(0.0), vec3(1.0));
    float falloff = cubicRadius.x * cubicRadius.y * cubicRadius.z;
    return 1.0 - pow(1.0 - pow(falloff, 1.5), 3.0);
}

// 把体积光混回原来的方块光：淡出乘强度当权重，零强度时原样返回。
vec3 ogxLpvApply(vec3 blockLight, vec4 texel, float falloff, float strength)
{
    return mix(blockLight, texel.rgb, ogxSaturate(falloff * strength));
}

// LPV 体积雾：沿视线指数步进，用三维密度图与 LPV 图累积照明。
// 参考实现直接调 `cloudVol` 与 `SampleLpvLinear`；库用同样布局的三维纹理代替。
vec4 ogxLpvFogMarch(vec3 origin, vec3 endPos, float dither, sampler3D densityTexture,
    sampler3D lpvTexture, vec3 cameraOffset, float lpvSize, float fadeLength, float minDensity,
    float mult, int sampleCount, float lpvBrightness, vec3 handLight, float torchAmount, bool vanillaMask)
{
    if (length(origin - endPos) < 0.001) return vec4(0.0, 0.0, 0.0, 1.0); // 没有长度就没有雾。
    vec3 rayStart = endPos - origin - cameraOffset; // 相机相对射线。
    float rayLength = length(rayStart); // 射线长度。
    rayStart *= min(rayLength, min(256.0, 1e6)) / max(rayLength, 1e-6); // 参考实现的距离上限。
    rayLength = length(rayStart);
    vec4 color = vec4(0.0, 0.0, 0.0, 1.0); // 累积颜色与透过率。
    const float expFactor = 11.0; // 指数步长。
    for (int i = 0; i < sampleCount; i++) // 固定步数。
    {
        float d = (pow(expFactor, float(i) + dither) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进比例。
        float dd = pow(expFactor, float(i) + dither) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        vec3 progress = cameraOffset + d * rayStart + origin; // 当前世界位置。
        float density = max(textureLod(densityTexture, progress, 0.0).r / 1000.0, minDensity) * mult; // 密度。
        float volumeCoeff = exp(-dd * density * rayLength); // 本段透过率。
        vec3 lpvPos = (progress - origin) / max(lpvSize, 1.0); // 体积坐标。
        vec3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘。
        float fade = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴淡出。
        if (fade < 0.01) break; // 体积外停止。
        vec3 sampleColor = textureLod(lpvTexture, lpvPos, 0.0).rgb; // LPV 光色。
        if (vanillaMask) sampleColor *= 1.0; // 原版遮罩由调用方预先乘进纹理。
        vec3 lighting = sampleColor * lpvBrightness * 25.0 * exp(-5.0 * (1.0 - ogxLuminance(sampleColor))); // 参考实现的亮度曲线。
        lighting += handLight * torchAmount * lpvBrightness * 0.04; // 手持光。
        color.rgb += (lighting - lighting * volumeCoeff) * color.a; // 累积散射。
        color.a *= volumeCoeff; // 累积透过率。
    }
    return color; // 交回 LPV 雾。
}

// 严格参考签名的 LPV 雾入口：密度场、LPV 图与手持光表都作为显式资源。
// 参考在循环里调用 cloudVol、GetLpvPosition、SampleLpvLinear 与 GetHandLight；
// 这里把密度场换成三维纹理，LPV 采样用库里的精确实现，手持光走同一套字节拆包。
vec4 ogxLpvFogMarchExact(vec3 origin, vec3 endPos, float dither,
    sampler3D densityTexture, sampler3D lpvTexture, vec3 cameraOffset, float lpvSize, float fadeLength,
    float minDensity, int vlSamples, int sampleCount, float lpvBrightness, float torchAmount,
    float caveDetection, float farPlane, vec3 relativeEyePosition, usampler1D blockDataTexture,
    int heldItemId, int heldItemId2, int frameCounter, vec2 blockSkyRange)
{
    if (length(origin - endPos) < 0.001) return vec4(0.0, 0.0, 0.0, 1.0); // 空段直接返回。
    float mult = float(vlSamples) / float(sampleCount) * 1.15; // 参考实现的样本数换算。
    float minimumDensity = minDensity; // 参考实现的最低密度，由调用方按选项给出。
    vec3 lpvRayStart = endPos - origin - cameraOffset; // 相机相对射线。
    float lpvRayLength = length(lpvRayStart); // 射线长度。
    lpvRayStart *= min(lpvRayLength, min(256.0, farPlane)) / lpvRayLength; // 参考实现的距离上限。
    lpvRayLength = length(lpvRayStart); // 截断后的长度。
    vec4 color = vec4(0.0, 0.0, 0.0, 1.0); // 累积颜色与透过率。
    const float expFactor = 11.0; // 指数步长。
    for (int i = 0; i < sampleCount; i++) // 固定样本数。
    {
        float d = (pow(expFactor, float(i) + dither) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 步进位置。
        float dd = pow(expFactor, float(i) + dither) * log(expFactor) / float(sampleCount) / (expFactor - 1.0); // 步长导数。
        vec3 rayProgress = cameraOffset + d * lpvRayStart + origin; // 当前世界位置。
        float density = 0.0; // 这一步的雾密度。
        float minimumDensityNow = minimumDensity; // 洞穴里抬高最低密度。
        if (caveDetection < 0.9999) density = textureLod(densityTexture, rayProgress, 0.0).r * (1.0 - caveDetection); // 密度场换成显式纹理。
        minimumDensityNow += caveDetection * minimumDensity; // 洞穴补偿。
        density = max(density / 1000.0, minimumDensityNow) * mult; // 参考实现的密度换算。
        float volumeCoeff = exp(-dd * density * lpvRayLength); // 本段透过率。
        vec3 lpvPos = ogxLpvPositionExplicit(rayProgress, vec3(0.0), lpvSize); // 体积坐标。
        vec3 cubicRadius = clamp(min(((lpvSize - 1.0) - lpvPos) / fadeLength, lpvPos / fadeLength), 0.0, 1.0); // 边缘淡出。
        float lpvFade = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴乘积。
        if (lpvFade < 0.01) break; // 走出体积就停。
        vec3 sampleColor = ogxLpvSampleLinear(lpvPos, lpvTexture, lpvTexture, frameCounter, lpvSize, blockSkyRange).rgb; // LPV 光色。
        vec3 lighting = sampleColor * lpvBrightness * 25.0
            * exp(-5.0 * (1.0 - dot(sampleColor, vec3(0.21, 0.72, 0.07)))); // 参考亮度曲线与亮度权重。
        float lightRange = 0.0; // 手持光范围。
        vec3 handLight1 = ogxHandLightFromBlockData(heldItemId, rayProgress, lightRange, blockDataTexture, relativeEyePosition); // 主手。
        vec3 handLight2 = ogxHandLightFromBlockData(heldItemId2, rayProgress, lightRange, blockDataTexture, relativeEyePosition); // 副手。
        lighting += (handLight1 + handLight2) * torchAmount * lpvBrightness * 0.04; // 手持光叠加。
        color.rgb += (lighting - lighting * volumeCoeff) * color.a; // 累积散射。
        color.a *= volumeCoeff; // 累积透过率。
    }
    return color; // 交回 LPV 雾。
}

#endif
