/*
生成文件：采样模块的 GLSL 330 版本，请勿手工修改。
源文件在库的源码目录中的同名模块，改动后运行构建脚本的生成命令。
用途：Minecraft 光影直接引入；同一份源还会生成 SPIR-V 供独立程序使用。
生成器只做类型名、关键字与取像素写法的等价转换，不改变算式和常数。
*/
/*
Omni 通用图形库采样模块：蓝噪声、时间抖动与拜尔抖动。
调用位置：任何需要每像素或每帧不同采样偏移的程序；Minecraft 光影由 `/omni-gfx/sampling.glsl` 引入。
可复制示例：
    vec2 n = ogxBlueNoise(noiseTexture, ivec2(pixel)); // 取一张蓝噪声。
    float d = ogxBayerTemporal(ivec2(pixel), 0); // 取每帧变化的拜尔值。
设计原因与取舍：
    噪声纹理、像素坐标和帧号全部由调用方传入，库不依赖任何引擎全局量。
    静态蓝噪声按六十四像素平铺；时间偏移用黄金比与塑料比错开，避免相邻帧重叠。
    取像素只用显式整数坐标，不用硬件过滤，因此同一份源能直接生成 SPIR-V 与 GLSL。
*/
#ifndef OGX_SAMPLING_INCLUDED
#define OGX_SAMPLING_INCLUDED

// 数学模块提供拜尔矩阵与两个时间步长。
#include "/omni-gfx/math.glsl"
// 显式取一个像素；Slang 的 `Load` 在生成 GLSL 时换成 `texelFetch`，两边语义相同。
vec4 ogxTexelFetch(sampler2D tex, ivec2 pixel, int level)
{
    return texelFetch(tex, pixel, level);
}

// 从蓝噪声纹理取当前像素的二维偏移；纹理边长六十四，按像素坐标取模平铺。
vec2 ogxBlueNoise(sampler2D noiseTexture, ivec2 pixel)
{
    return ogxTexelFetch(noiseTexture, pixel % 64, 0).xy;
}

// 加上帧号偏移，得到每帧变化、六十四帧一循环的二维抖动。
vec2 ogxBlueNoiseTemporal(sampler2D noiseTexture, ivec2 pixel, int frame)
{
    vec2 base = ogxBlueNoise(noiseTexture, pixel);
    return fract(base + vec2(OGX_GOLDEN_RATIO, OGX_PLASTIC_RATIO) * float(frame % 64));
}

// 每帧平移的拜尔抖动，一百二十八帧一循环，适合需要低差异序列的场合。
// 黄金比步进让相邻帧的偏移不重复，同时保持单帧内的空间分布。
float ogxBayerTemporal(ivec2 pixel, int frame)
{
    return fract(ogxBayer64(vec2(pixel)) + OGX_GOLDEN_RATIO * float(frame % 128));
}

#endif
