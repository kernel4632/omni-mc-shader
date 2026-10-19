/*
通用图形库云模块：云的光照相位与顶部曲线。
调用位置：任何需要体积云光照形状的程序；本仓库由 `effects/cloud/volumetric.glsl` 转发调用。
可复制示例：
    float p = gfx_henyey_greenstein(cosAngle, 0.8); // 前向散射相位。
    float t = gfx_cloud_top_curve(x); // 云的顶部圆润曲线。
设计原因与取舍：
    只做纯数学，不读取噪声纹理、云层高度或选项；采样与密度仍由调用方负责。
    公式照 iterationT 原程序保留，迁移只改名字。
*/
#ifndef GFX_CLOUD_INCLUDED
#define GFX_CLOUD_INCLUDED

#include "/gfx/math.glsl"

// 亨耶-格林斯坦相位：描述云滴把光往哪个方向散，参数越大越集中在前方。
float gfx_henyey_greenstein(float cosAngle, float g){
	float num = 1.0 - g * g; // 分子，控制整体强度。
	float denom = 1.0 + g * g - 2.0 * g * cosAngle; // 分母，越靠前越小。
	float inverse = inversesqrt(denom); // 分母的平方根倒数。
	return num * inverse * inverse * inverse * (0.25 / GFX_PI); // 归一化后返回。
}

// 云的顶部曲线：把一到零的坐标变成圆润的凸起。
float gfx_cloud_top_curve(float x){
	x = x - 1.0; // 平移到顶点。
	return 1.0 - x * x; // 开口向下的抛物线。
}

#endif
