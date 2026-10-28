/*
通用图形库采样模块：蓝噪声、时间抖动与拜尔抖动。
调用位置：任何需要每像素或每帧不同采样偏移的程序；本仓库由 `common/noise.glsl` 转发调用。
可复制示例：
    vec2 n = gfx_blue_noise(noiseTexture, ivec2(pixel)); // 取一张蓝噪声。
    float d = gfx_bayer_temporal(ivec2(pixel), 0); // 取每帧变化的拜尔值。
设计原因与取舍：
    噪声纹理、像素坐标和帧号全部由调用方传入，库不依赖任何引擎全局量。
    做法与 iterationT 原程序一致：蓝噪声按六十四像素平铺，时间偏移用黄金比与塑料比错开。
    本模块依赖 `math.glsl` 里的拜尔函数，单独复制时要一起带上。
*/
#ifndef GFX_SAMPLING_INCLUDED
#define GFX_SAMPLING_INCLUDED

// 拜尔矩阵来自数学模块。
#include "math.glsl"

#define GFX_GOLDEN_RATIO 1.61803398875 // 黄金比，用来让帧间偏移尽量不重合。
#define GFX_PLASTIC_RATIO 1.32471795724 // 塑料比，给第二个通道用不同的步长。

// 从蓝噪声纹理取当前像素的二维偏移。
vec2 gfx_blue_noise(sampler2D noiseTexture, ivec2 pixel){ // 输入噪声纹理与像素。
	return texelFetch(noiseTexture, pixel % 64, 0).xy; // 纹理边长六十四，取模平铺。
}

// 加上帧号偏移，得到每帧变化、六十四帧一循环的二维抖动。
vec2 gfx_blue_noise_temporal(sampler2D noiseTexture, ivec2 pixel, int frame){ // 在静态噪声上叠帧偏移。
	vec2 base = texelFetch(noiseTexture, pixel % 64, 0).xy; // 先取静态蓝噪声。
	return fract(base + vec2(GFX_GOLDEN_RATIO, GFX_PLASTIC_RATIO) * float(frame % 64)); // 两个通道用不同步长错开。
}

// 每帧平移的拜尔抖动，一百二十八帧一循环，适合需要低差异序列的场合。
float gfx_bayer_temporal(ivec2 pixel, int frame){ // 输入像素与帧号。
	return fract(gfx_bayer64(vec2(pixel)) + GFX_GOLDEN_RATIO * float(frame % 128)); // 黄金比步进让相邻帧不重复。
}

#endif
