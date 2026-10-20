/*
通用图形库全局光模块：环境遮蔽的多弹射补偿。
调用位置：任何需要把环境遮蔽混回表面的程序；本仓库由 `effects/lighting/gtao.glsl` 转发调用。
可复制示例：
    vec3 ao = gfx_ao_multi_bounce(occlusion, albedo); // 按底色补偿一次反弹。
设计原因与取舍：
    只做纯数学，不读取深度、法线或画面；遮蔽采样仍由调用方负责。
    多项式照原程序保留，避免暗部被压死。
*/
#ifndef GFX_GI_INCLUDED
#define GFX_GI_INCLUDED

// 环境遮蔽多弹射：底色越亮补光越多，避免墙角完全变黑。
vec3 gfx_ao_multi_bounce(float ao, vec3 albedo){
	vec3 a = 2.0404 * albedo - 0.3324; // 一次项系数。
	vec3 b = -4.7951 * albedo + 0.6417; // 二次项系数。
	vec3 c = 2.7552 * albedo + 0.6903; // 三次项系数。
	return max(vec3(ao), ((ao * a + b) * ao + c) * ao); // 取多项式与原始遮蔽的较大值。
}

#endif
