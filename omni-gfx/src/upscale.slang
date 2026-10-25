/*
Omni 通用图形库放大与锐化模块：边缘方向重采样、对比度自适应锐化与放大后锐化。
调用位置：任何把低分辨率画面放大到目标分辨率并恢复清晰度的程序；Minecraft 光影由
    `/omni-gfx/upscale.glsl` 引入，`rendering/clarity/upscale.glsl` 只保留选项换算。
可复制示例：ogxFsrEasu 把输入画面放大，ogxCas 再做对比度自适应锐化。
设计原因与取舍：采样器与画面尺寸由调用方传入，本模块不声明采样器、不读选项；
    公式与 iterationT 的边缘方向重采样和对比度自适应锐化逐行一致。
    旧实现直接用了宿主的 `saturate` 宏，这里改成库自己的夹紧函数，算式完全相同，
    但模块可以脱离光影单独编译。
*/
#ifndef OGX_UPSCALE_INCLUDED
#define OGX_UPSCALE_INCLUDED

// 数学模块提供亮度、夹紧与单位化。
#include "math.slang"

// 单个采样点按离重采样中心的距离给权重，超出钳位半径的样本不再增加贡献。
// 两层权重相乘让核在中心为一、边缘平滑收零，避免放大后出现一圈硬边。
void ogxFsrEasuTap(inout float3 aC, inout float aW, float2 off, float2 dir, float2 len, float lob, float clp, float3 c)
{
    float2 rotOff = float2(dot(off, dir), dot(off, float2(-dir.y, dir.x))); // 把偏移转到与边缘对齐的坐标系。
    rotOff *= len; // 按边缘方向拉伸，让各向异性核沿边缘铺得更长。
    float d2 = min(dot(rotOff, rotOff), clp); // 到中心的距离平方，夹在钳位半径内。
    float wB = 0.4 * d2 - 1.0; // 外层权重多项式的一步。
    float wA = lob * d2 - 1.0; // 内层权重多项式的一步。
    wB *= wB; // 外层权重取平方。
    wA *= wA; // 内层权重取平方。
    wB = 1.5625 * wB - 0.5625; // 外层权重成形。
    float w = wB * wA; // 内外层权重相乘得到最终权重。
    aC += c * w; // 累加颜色。
    aW += w; // 累加权重。
}

// 用四组邻域估计边缘方向与长度，四组是四个子像素象限，权重是子像素面积。
void ogxFsrEasuSet(inout float2 dir, inout float len, float w, float lA, float lB, float lC, float lD, float lE)
{
    float lenX = 1.0 / max(abs(lD - lC), abs(lC - lB)); // 水平方向长度倒数，由相邻亮度差决定。
    float dirX = lD - lB; // 水平亮度梯度。
    dir.x += dirX * w; // 按子像素面积加权累加水平方向。
    lenX = ogxSaturate(abs(dirX) * lenX); // 梯度越大越像边缘。
    lenX *= lenX; // 平方让弱边缘更快衰减。
    len += lenX * w; // 累加水平长度。
    float lenY = 1.0 / max(abs(lE - lC), abs(lC - lA)); // 竖直方向长度倒数。
    float dirY = lE - lA; // 竖直亮度梯度。
    dir.y += dirY * w; // 按子像素面积加权累加竖直方向。
    lenY = ogxSaturate(abs(dirY) * lenY); // 梯度越大越像边缘。
    lenY *= lenY; // 平方。
    len += lenY * w; // 累加竖直长度。
}

// 把输入画面按边缘方向重采样放大到目标分辨率，返回放大后的颜色。
// `fragCoord` 是输出像素坐标，`inputScreenSize` 是输入画面尺寸，`outputScreenSize` 是输出尺寸。
float3 ogxFsrEasu(Sampler2D inputTex, float2 fragCoord, float2 inputScreenSize, float2 outputScreenSize)
{
    float2 sizeRatio = inputScreenSize / outputScreenSize; // 输入相对输出的比例，用于把输出坐标映射回输入。
    float2 subPixelOffset = fragCoord * sizeRatio - 0.5; // 输出像素落在输入像素网格里的位置。
    float2 sampleCenter = floor(subPixelOffset); // 最近的低分辨率整数像素。
    subPixelOffset -= sampleCenter; // 去掉整数部分，只留子像素偏移。
    int2 texelCoordF = int2(sampleCenter); // 中心纹素坐标。
    float3 sampleB = inputTex.Load(int3(texelCoordF + int2(0, -1), 0)).rgb; // 上方邻域样本。
    float3 sampleC = inputTex.Load(int3(texelCoordF + int2(1, -1), 0)).rgb; // 右上邻域。
    float3 sampleE = inputTex.Load(int3(texelCoordF + int2(-1, 0), 0)).rgb; // 左侧邻域。
    float3 sampleF = inputTex.Load(int3(texelCoordF + int2(0, 0), 0)).rgb; // 中心样本。
    float3 sampleG = inputTex.Load(int3(texelCoordF + int2(1, 0), 0)).rgb; // 右侧邻域。
    float3 sampleH = inputTex.Load(int3(texelCoordF + int2(2, 0), 0)).rgb; // 右侧隔一个的邻域。
    float3 sampleI = inputTex.Load(int3(texelCoordF + int2(-1, 1), 0)).rgb; // 左下邻域。
    float3 sampleJ = inputTex.Load(int3(texelCoordF + int2(0, 1), 0)).rgb; // 下方邻域。
    float3 sampleK = inputTex.Load(int3(texelCoordF + int2(1, 1), 0)).rgb; // 右下邻域。
    float3 sampleL = inputTex.Load(int3(texelCoordF + int2(2, 1), 0)).rgb; // 右下隔一个的邻域。
    float3 sampleN = inputTex.Load(int3(texelCoordF + int2(0, 2), 0)).rgb; // 下方隔一个的邻域。
    float3 sampleO = inputTex.Load(int3(texelCoordF + int2(1, 2), 0)).rgb; // 右下再隔一个的邻域。
    float luminanceB = ogxLuminance(sampleB); // 各邻域亮度，用于估计边缘。
    float luminanceC = ogxLuminance(sampleC); // 右上亮度。
    float luminanceE = ogxLuminance(sampleE); // 左侧亮度。
    float luminanceF = ogxLuminance(sampleF); // 中心亮度。
    float luminanceG = ogxLuminance(sampleG); // 右侧亮度。
    float luminanceH = ogxLuminance(sampleH); // 右二亮度。
    float luminanceI = ogxLuminance(sampleI); // 左下亮度。
    float luminanceJ = ogxLuminance(sampleJ); // 下方亮度。
    float luminanceK = ogxLuminance(sampleK); // 右下亮度。
    float luminanceL = ogxLuminance(sampleL); // 右二下亮度。
    float luminanceN = ogxLuminance(sampleN); // 下二亮度。
    float luminanceO = ogxLuminance(sampleO); // 右下二亮度。
    float2 dir = float2(0.0); // 边缘方向。
    float len = 0.0; // 边缘长度。
    ogxFsrEasuSet(dir, len, (1.0 - subPixelOffset.x) * (1.0 - subPixelOffset.y), luminanceB, luminanceE, luminanceF, luminanceG, luminanceJ); // 左下子像素象限。
    ogxFsrEasuSet(dir, len, subPixelOffset.x * (1.0 - subPixelOffset.y), luminanceC, luminanceF, luminanceG, luminanceH, luminanceK); // 右下子像素象限。
    ogxFsrEasuSet(dir, len, (1.0 - subPixelOffset.x) * subPixelOffset.y, luminanceF, luminanceI, luminanceJ, luminanceK, luminanceN); // 左上子像素象限。
    ogxFsrEasuSet(dir, len, subPixelOffset.x * subPixelOffset.y, luminanceG, luminanceJ, luminanceK, luminanceL, luminanceO); // 右上子像素象限。
    float2 dir2 = dir * dir; // 方向各分量平方。
    float dirR = dir2.x + dir2.y; // 方向长度平方。
    bool zro = dirR < (1.0 / 32768.0); // 极小的方向视为没有边缘。
    dirR = rsqrt(dirR); // 方向长度倒数。
    dirR = zro ? 1.0 : dirR; // 没有边缘时用一，避免除零。
    dir.x = zro ? 1.0 : dir.x; // 没有边缘时默认水平方向。
    dir *= float2(dirR); // 归一化方向。
    len = len * 0.5; // 长度取一半。
    len *= len; // 平方。
    float stretch = dot(dir, dir) / (max(abs(dir.x), abs(dir.y))); // 边缘各向异性比例。
    float2 len2 = float2(1.0 + (stretch - 1.0) * len, 1.0 - 0.5 * len); // 沿边缘与垂直方向的不同拉伸。
    float lob = 0.5 - 0.29 * len; // 核宽度参数。
    float clp = 1.0 / lob; // 核钳位半径。
    float3 min4 = min(min(sampleF, sampleG), min(sampleJ, sampleK)); // 中心四邻最小值，限制重采样范围。
    float3 max4 = max(max(sampleF, sampleG), max(sampleJ, sampleK)); // 中心四邻最大值。
    float3 aC = float3(0.0); // 加权颜色。
    float aW = 0.0; // 权重和。
    ogxFsrEasuTap(aC, aW, float2(0.0, -1.0) - subPixelOffset, dir, len2, lob, clp, sampleB); // 上方样本。
    ogxFsrEasuTap(aC, aW, float2(1.0, -1.0) - subPixelOffset, dir, len2, lob, clp, sampleC); // 右上样本。
    ogxFsrEasuTap(aC, aW, float2(-1.0, 0.0) - subPixelOffset, dir, len2, lob, clp, sampleE); // 左侧样本。
    ogxFsrEasuTap(aC, aW, float2(0.0, 0.0) - subPixelOffset, dir, len2, lob, clp, sampleF); // 中心样本。
    ogxFsrEasuTap(aC, aW, float2(1.0, 0.0) - subPixelOffset, dir, len2, lob, clp, sampleG); // 右侧样本。
    ogxFsrEasuTap(aC, aW, float2(2.0, 0.0) - subPixelOffset, dir, len2, lob, clp, sampleH); // 右二样本。
    ogxFsrEasuTap(aC, aW, float2(-1.0, 1.0) - subPixelOffset, dir, len2, lob, clp, sampleI); // 左下样本。
    ogxFsrEasuTap(aC, aW, float2(0.0, 1.0) - subPixelOffset, dir, len2, lob, clp, sampleJ); // 下方样本。
    ogxFsrEasuTap(aC, aW, float2(1.0, 1.0) - subPixelOffset, dir, len2, lob, clp, sampleK); // 右下样本。
    ogxFsrEasuTap(aC, aW, float2(2.0, 1.0) - subPixelOffset, dir, len2, lob, clp, sampleL); // 右二下样本。
    ogxFsrEasuTap(aC, aW, float2(0.0, 2.0) - subPixelOffset, dir, len2, lob, clp, sampleN); // 下二样本。
    ogxFsrEasuTap(aC, aW, float2(1.0, 2.0) - subPixelOffset, dir, len2, lob, clp, sampleO); // 右下二样本。
    return min(max4, max(min4, aC / aW)); // 归一化后夹在中心四邻范围内，抑制过冲。
}

// 对比度自适应锐化：按十字邻域的对比度决定锐化强度，平坦处几乎不动。
// `sharpness` 是百分制锐化量，`denoise` 打开时按十字噪声再压低一次。
float3 ogxCas(Sampler2D colorTex, float3 sampleE, int2 texelCoord, float sharpness, bool denoise)
{
    float3 sampleB = colorTex.Load(int3(texelCoord + int2(0, -1), 0)).rgb; // 上方样本。
    float3 sampleD = colorTex.Load(int3(texelCoord + int2(-1, 0), 0)).rgb; // 左侧样本。
    float3 sampleF = colorTex.Load(int3(texelCoord + int2(1, 0), 0)).rgb; // 右侧样本。
    float3 sampleH = colorTex.Load(int3(texelCoord + int2(0, 1), 0)).rgb; // 下方样本。
    float luminanceB = ogxLuminance(sampleB); // 上方亮度。
    float luminanceD = ogxLuminance(sampleD); // 左侧亮度。
    float luminanceE = ogxLuminance(sampleE); // 中心亮度。
    float luminanceF = ogxLuminance(sampleF); // 右侧亮度。
    float luminanceH = ogxLuminance(sampleH); // 下方亮度。
    float minCross = min(min(luminanceB, luminanceD), min(luminanceE, min(luminanceF, luminanceH))); // 十字邻域最小亮度。
    float maxCross = max(max(luminanceB, luminanceD), max(luminanceE, max(luminanceF, luminanceH))); // 十字邻域最大亮度。
    float weight = sqrt(ogxSaturate(min(minCross, 2.0 - maxCross) / maxCross)) * (-0.1 - sharpness * 0.01); // 对比度越低权重越接近零，锐化越弱。
    if (denoise) // 开启降噪时按十字噪声再压低一次。
    {
        float noise = luminanceB * 0.25 + luminanceD * 0.25 + luminanceF * 0.25 + luminanceH * 0.25 - luminanceE; // 中心与四邻均值之差就是噪声估计。
        noise = ogxSaturate(abs(noise) / (maxCross - minCross)); // 归一化成零到一。
        weight *= 1.0 - 0.5 * noise; // 噪声越大锐化越弱。
    }
    float3 sharpen = (sampleB * weight + sampleD * weight + sampleF * weight + sampleH * weight + sampleE) / (1.0 + 4.0 * weight); // 用中心减去的邻域平均做锐化。
    return max(sharpen, float3(0.0)); // 去掉负值。
}

// 放大后的锐化：邻域布局与上面相同，样本取自放大输出画面，用于压低放大带来的软边。
float3 ogxFsr1(Sampler2D upscaledTex, int2 texelCoord, float sharpness, bool denoise)
{
    float3 sampleE = upscaledTex.Load(int3(texelCoord + int2(0, 0), 0)).rgb; // 中心样本。
    return ogxCas(upscaledTex, sampleE, texelCoord, sharpness, denoise); // 十字对比度判断与上面共用一份。
}

#endif
