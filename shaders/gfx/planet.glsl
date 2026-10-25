/*
行星模块适配层：末地行星本体、光环与大气已迁到生成库。
调用位置：末地天空与末地反射的绑定层引用本文件；效果层只保留时间、行星阴影强度与噪声贴图，
    算法只在 `omni-gfx/src/planet.slang` 一份。
可复制示例：`gfx_planet_end(color, eye, rayDir, lightDir, shadowVector, time, planetShadow, noiseTex);`
设计原因与取舍：函数名、参数顺序与就地修改颜色的写法保持原样，调用点无需改动，默认画面不会漂移；
    行星半径与相机高度是算法的一部分，留在生成库；时间与阴影强度由调用方传入。
*/
#ifndef GFX_PLANET_INCLUDED
#define GFX_PLANET_INCLUDED

// 通用数学、大气与迁移后的行星实现。
// 下面三行只引入依赖，不在这里写任何算式。
#include "/gfx/math.glsl"
#include "/gfx/atmosphere.glsl"
#include "/omni-gfx/planet.glsl"

// 画一整颗行星：先与地表球求交，再叠光环与大气，最后把环带的遮挡乘回天空。
// 颜色就地修改，调用方直接拿到叠加后的天空。
void gfx_planet_end(inout vec3 color, in vec3 eye, in vec3 rayDir, in vec3 lightDir,
        in vec3 shadowVector, float time, float planetShadow, sampler2D noiseTex){
	ogxPlanetEnd(color, eye, rayDir, lightDir, shadowVector, time, planetShadow, noiseTex); // 实现在生成库。
}

#endif
