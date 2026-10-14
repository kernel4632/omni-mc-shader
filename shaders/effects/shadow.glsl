// 阴影：阴影入口写深度，光照与雾读取；示例 omniShadow(world, normal)。
#ifndef OMNI_SHADOW // 地形与雾共用同一阴影定义。
#define OMNI_SHADOW // 多次引用不重复声明选项与函数。
// @effect {"label":{"zh_cn":"阴影","en_us":"Shadows"}}
// @option {"label":{"zh_cn":"开启阴影","en_us":"Enable shadows"}}
#define OMNI_SHADOW_ENABLED
// @option {"label":{"zh_cn":"阴影质量","en_us":"Shadow samples"},"description":{"zh_cn":"一为单次比较，三或五为柔化采样边长。","en_us":"One comparison or a three/five wide PCF kernel."}}
#define OMNI_SHADOW_QUALITY 3 // [1 3 5]
// @option {"label":{"zh_cn":"阴影柔化","en_us":"Shadow softness"},"slider":true}
#define OMNI_SHADOW_SOFTNESS 1.5 // [0.5 1.0 1.5 2.0 3.0]
// Iris原生阴影常量必须直接使用字面量，菜单范围仍从这两行唯一读取。
// @option {"label":{"zh_cn":"阴影分辨率","en_us":"Shadow resolution"},"description":{"zh_cn":"Iris直接读取该原生常量并分配shadowtex。","en_us":"Iris reads this native constant for shadowtex allocation."}}
const int shadowMapResolution = 2048; // [1024 2048 4096]
// @option {"label":{"zh_cn":"阴影距离","en_us":"Shadow distance"},"description":{"zh_cn":"Iris直接读取该原生常量并设置阴影范围。","en_us":"Iris reads this native constant for shadow range."}}
const float shadowDistance = 128.0; // [64.0 128.0 192.0 256.0]
// 共用坐标与归一化。
#include "/common/coordinates.glsl"
#include "/common/math.glsl"
vec3 omniShadowCoord(vec3 world) {
    vec4 p = shadowProjection * shadowModelView * vec4(world, 1.0); // 世界位置投向阴影相机。
    return p.xyz / p.w * 0.5 + 0.5; // 写入者与读取者使用相同无畸变投影。
}
float omniShadow(vec3 world, vec3 normal) {
#ifdef OMNI_SHADOW_ENABLED
    if (length(world) > shadowDistance * 0.95) return 1.0; // 超出阴影覆盖使用环境照明。
    vec3 n = mat3(gbufferModelViewInverse) * normal; // 视空间法线转世界空间。
    vec3 p = omniShadowCoord(world + n * 0.035); // 法线偏移减少自身条纹。
    if (any(lessThanEqual(p, vec3(0))) || any(greaterThanEqual(p, vec3(1)))) return 1.0; // 阴影图外不采样边缘。
    float result = 0.0; // 累计真实深度比较。
    for (int y = 0; y < OMNI_SHADOW_QUALITY; y++) { // 柔化核纵向覆盖邻近深度。
        for (int x = 0; x < OMNI_SHADOW_QUALITY; x++) { // 柔化核横向覆盖邻近深度。
            vec2 offset = (vec2(x,y) - float(OMNI_SHADOW_QUALITY - 1) * 0.5) * OMNI_SHADOW_SOFTNESS / float(shadowMapResolution);
            result += step(p.z - 0.0006, texture(shadowtex0, p.xy + offset).r); // 百分比近邻柔化。
        }
    }
    return mix(result / float(OMNI_SHADOW_QUALITY * OMNI_SHADOW_QUALITY), 1.0, smoothstep(shadowDistance * 0.8, shadowDistance * 0.95, length(world))); // 距离边缘平滑淡出。
#else
    return 1.0; // 关闭时编译移除所有阴影采样。
#endif
}
#endif
