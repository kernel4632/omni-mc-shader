// 植被：只移动指定叶片与植物顶点，示例 omniVegetation(world, blockId, top)。
#ifndef OMNI_VEGETATION
#define OMNI_VEGETATION
// @effect {"label":{"zh_cn":"植被","en_us":"Vegetation"}}
// @option {"label":{"zh_cn":"植被摆动","en_us":"Vegetation wind"}}
#define OMNI_VEGETATION_WIND
// @option {"label":{"zh_cn":"摆动强度","en_us":"Wind strength"},"slider":true}
#define OMNI_WIND_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"摆动速度","en_us":"Wind speed"},"slider":true}
#define OMNI_WIND_SPEED 1.0 // [0.5 1.0 1.5 2.0]
// 共用噪声与时间。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"
vec3 omniVegetation(vec3 world, float blockId, float top) {
#ifdef OMNI_VEGETATION_WIND
    if (blockId < 10001.0 || blockId > 10002.0) return world; // 石头与其他表面不移动。
    vec3 absolute = world + cameraPosition; // 噪声固定在世界，移动镜头不改变风。
    float amount = blockId == 10002.0 ? top : 0.5; // 小植物固定根部，叶片整块轻摆。
    float wave = sin(frameTimeCounter*1.7*OMNI_WIND_SPEED+absolute.x*0.7+absolute.z*0.5); // 空间相位让风连续传递；速度选项整体快慢缩放。
    world.xz += vec2(0.08,0.05)*wave*amount*OMNI_WIND_STRENGTH*(1.0+rainStrength); // 雨天增加风幅；强度选项整体放大或缩小。
#endif
    return world; // 关闭时保留原顶点。
}
#endif
