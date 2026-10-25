/*
采样模块适配层：蓝噪声、时间抖动与拜尔抖动已迁到生成库。
调用位置：`shaders/rendering/**` 里需要每像素或每帧不同抖动的地方；算式只在
    `omni-gfx/src/sampling.slang` 一份。
可复制示例：`vec2 n = gfx_blue_noise(noiseTexture, ivec2(pixel));` 取一张蓝噪声。
设计原因与取舍：函数名、参数顺序与返回类型保持原样，调用点无需改动，默认画面不会漂移；
    噪声纹理、像素坐标与帧号全部由调用方传入，本文件不复制任何抖动常数。
*/
#ifndef GFX_SAMPLING_INCLUDED
#define GFX_SAMPLING_INCLUDED

// 迁移后的采样实现：蓝噪声、时间抖动与拜尔抖动。
#include "/omni-gfx/sampling.glsl"

// 两个无理步长接到生成库的常量上，旧代码仍可读取。
#define GFX_GOLDEN_RATIO OGX_GOLDEN_RATIO
#define GFX_PLASTIC_RATIO OGX_PLASTIC_RATIO

// 从蓝噪声纹理取当前像素的二维偏移。
vec2 gfx_blue_noise(sampler2D noiseTexture, ivec2 pixel){ return ogxBlueNoise(noiseTexture, pixel); } // 实现在生成库。

// 加上帧号偏移，得到每帧变化、六十四帧一循环的二维抖动。
vec2 gfx_blue_noise_temporal(sampler2D noiseTexture, ivec2 pixel, int frame){ return ogxBlueNoiseTemporal(noiseTexture, pixel, frame); } // 实现在生成库。

// 每帧平移的拜尔抖动，一百二十八帧一循环。
float gfx_bayer_temporal(ivec2 pixel, int frame){ return ogxBayerTemporal(pixel, frame); } // 实现在生成库。

#endif
