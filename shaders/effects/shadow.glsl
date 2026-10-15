// 阴影：阴影入口写深度，光照与雾读取；示例 omniShadow(world, normal)。
// 职责：定义阴影选项、阴影图坐标与遮挡查询，供阴影深度绘制、光照和体积雾共用。
// 调用位置：effects/sunlight.glsl 与 effects/fog.glsl 引入后调用；rendering/shadow.glsl 复用其中选项。
// 可复制示例：`float lit = omniShadow(world, normal); vec3 p = omniShadowCoord(world);`
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
// @option {"label":{"zh_cn":"阴影偏置","en_us":"Shadow bias"},"description":{"zh_cn":"比较深度时留出的余量；太小会出现自身条纹，太大会让阴影脱离物体。","en_us":"Depth margin for the comparison; too small causes acne, too large detaches shadows."},"slider":true}
#define OMNI_SHADOW_BIAS 0.0006 // [0.0002 0.0006 0.0012 0.002]
// @option {"label":{"zh_cn":"法线偏移","en_us":"Normal offset"},"description":{"zh_cn":"比较点沿法线抬起的距离，用来减少贴地阴影的自身条纹。","en_us":"Lifts the sample along the normal to reduce self-shadowing on flat surfaces."},"slider":true}
#define OMNI_SHADOW_OFFSET 0.035 // [0.0 0.02 0.035 0.06]
// 共用坐标与归一化。
#include "/common/coordinates.glsl"
#include "/common/math.glsl"
// 相机相对世界位置投向阴影相机，输出零至一的阴影图坐标。
vec3 omniShadowCoord(vec3 world) {
    vec4 clip = shadowProjection * shadowModelView * vec4(world, 1.0); // 世界位置投向阴影相机。
    if (abs(clip.w) < 1e-6) return vec3(-1.0); // 齐次分量退化时返回图外坐标，交给读取者保守回退。
    return clip.xyz / clip.w * 0.5 + 0.5; // 写入者与读取者使用相同无畸变投影。
}
// 阴影可见度：零为全遮蔽，一为无遮蔽；关闭、越界或退化时保守返回一。
float omniShadow(vec3 world, vec3 normal) {
#ifdef OMNI_SHADOW_ENABLED
    float worldDistance = length(world); // 相机相对世界距离，用于覆盖判断与边缘淡出。
    if (worldDistance > shadowDistance * 0.95) return 1.0; // 超出阴影覆盖使用环境照明。
    vec3 n = mat3(gbufferModelViewInverse) * normal; // 视空间法线转世界空间。
    vec3 p = omniShadowCoord(world + n * OMNI_SHADOW_OFFSET); // 法线偏移减少自身条纹，偏移量可调。
    if (any(lessThanEqual(p, vec3(0.0))) || any(greaterThanEqual(p, vec3(1.0)))) return 1.0; // 阴影图外不采样边缘。
    float resolution = max(float(shadowMapResolution), 1.0); // 分辨率退化时采样偏移不会变成无穷。
    float result = 0.0; // 累计真实深度比较。
    int kernel = max(OMNI_SHADOW_QUALITY, 1); // 质量退化时至少比较一次。
    for (int y = 0; y < kernel; y++) { // 柔化核纵向覆盖邻近深度。
        for (int x = 0; x < kernel; x++) { // 柔化核横向覆盖邻近深度。
            vec2 offset = (vec2(x, y) - float(kernel - 1) * 0.5) * OMNI_SHADOW_SOFTNESS / resolution; // 柔化核内采样偏移。
            result += step(p.z - OMNI_SHADOW_BIAS, texture(shadowtex0, p.xy + offset).r); // 百分比近邻柔化，比较余量可调。
        }
    }
    float lit = result / float(kernel * kernel); // 未遮蔽采样占比。
    return mix(lit, 1.0, smoothstep(shadowDistance * 0.8, shadowDistance * 0.95, worldDistance)); // 距离边缘平滑淡出。
#else
    return 1.0; // 关闭时编译移除所有阴影采样。
#endif
}
#endif
