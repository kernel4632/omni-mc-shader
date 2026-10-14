// 雾：合成阶段处理距离、高度、水下和体积散射；示例 omniFog(color, view, world)。
#ifndef OMNI_FOG
#define OMNI_FOG
// @effect {"label":{"zh_cn":"雾与空气","en_us":"Fog"}}
// @option {"label":{"zh_cn":"距离雾强度","en_us":"Distance fog"},"slider":true}
#define OMNI_FOG_DENSITY 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"高度雾强度","en_us":"Height fog"},"slider":true}
#define OMNI_HEIGHT_FOG 0.5 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"体积光","en_us":"Volumetric light"}}
//#define OMNI_VOLUMETRIC_LIGHT
// 阴影图提供空气是否受光的依据。
#include "/effects/shadow.glsl"
#include "/effects/sky.glsl"
// 调用位置：rendering/composite.glsl；示例：omniFog(color, view, world)。
vec3 omniFog(vec3 color, vec3 view, vec3 world) {
    float distance = min(length(view),32000.0); // 避免背景重建造成指数溢出。
    float density = (0.0015 + rainStrength * 0.004) * OMNI_FOG_DENSITY; // 雨天缩短能见度。
    density += exp(-max(cameraPosition.y + world.y * 0.5 - 64.0,-40.0)*0.035) * 0.001 * OMNI_HEIGHT_FOG; // 沿线中点高度近似。
    vec3 atmosphere = omniSky(omniNormalize(world)); // 空气色与天空协调。
#ifdef OMNI_NETHER
    density *= 4.0; // 下界浓雾。
    atmosphere = omniLinear(fogColor); // 下界保留实际生物群系雾色。
#elif defined OMNI_END
    atmosphere = omniSky(omniNormalize(world)); // 末地只使用自定义环境色，不引入太阳光柱。
#endif
    if (isEyeInWater == 1) {
        return color * exp(-vec3(0.18,0.065,0.035)*distance) + vec3(0.015,0.09,0.12)*(1.0-exp(-distance*0.08)); // 水下按波段吸收。
    }
#ifdef OMNI_VOLUMETRIC_LIGHT
#if !defined OMNI_NETHER && !defined OMNI_END
    float scattering = 0.0; // 沿视线积累真实阴影可见性。
    for (int i=0;i<12;i++) {
        float t = (float(i)+0.5)/12.0; // 等距中点积分。
        vec3 sampleWorld = world*t; // 沿世界空间视线取样，避免把视空间法线误传给阴影。
        vec3 sampleNormal = omniNormalize(mat3(gbufferModelView)*vec3(0.0,1.0,0.0)); // 阴影接口接收视空间法线。
        scattering += omniShadow(sampleWorld, sampleNormal) * exp(-density*distance*t); // 主世界阴影遮挡产生光柱。
    }
    vec3 light = omniNormalize(shadowLightPosition); // 当前主光源方向。
    float phase = 0.04 + pow(max(dot(omniNormalize(view),light),0.0),8.0); // 前向散射强调天体方向。
    color += vec3(0.75,0.68,0.5)*scattering/12.0*(1.0-exp(-density*distance))*phase; // 光柱受实际空气密度控制。
#endif
#endif
    return mix(color,atmosphere,1.0-exp(-density*distance)); // 消光与空气散射共同组合。
}
#endif
