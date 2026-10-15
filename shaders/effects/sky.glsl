/*
天空：算出主世界的昼夜天空、星空，以及下界和末地的环境底色，供背景画面和屏幕外反射共用。
调用位置：effects/fog.glsl 与 effects/reflection.glsl 调用，经 atmosphere.glsl、cloud.glsl 汇入 rendering/lighting.glsl 的背景绘制。
可复制示例（直接照抄，`worldDirection` 与 `ray` 都是世界空间方向）：
    `vec3 sky = omniSky(worldDirection);`                              背景天空颜色。
    `vec3 reflected = omniSky(mat3(gbufferModelViewInverse) * ray);`   屏幕外反射采样同一片天空。
设计原因：天空是"方向到颜色"的纯函数，只吃一个世界方向，所以背景、反射和雾能用同一个方向调它，各自不用重复判断昼夜。
取舍：怎么把颜色画到屏幕由调用方决定，这里不出图也不读深度；代价是每个调用点都得给出正确的世界方向。
*/
#ifndef OMNI_SKY
#define OMNI_SKY
// @effect {"label":{"zh_cn":"天空","en_us":"Sky"}}
// @option {"label":{"zh_cn":"星空强度","en_us":"Star brightness"},"slider":true}
#define OMNI_STAR_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"天空饱和度","en_us":"Sky saturation"},"slider":true}
#define OMNI_SKY_SATURATION 1.0 // [0.5 0.75 1.0 1.25]
// @option {"label":{"zh_cn":"下界氛围色","en_us":"Nether palette"},"description":{"zh_cn":"用程序化混合替代固定下界雾色，覆盖荒原、灵魂沙谷、绯红与诡异森林和玄武岩。","en_us":"Replaces a fixed nether fog colour with a procedural blend of nether biomes."}}
#define OMNI_NETHER_COLOR 1 // [0 1]
// 天体、雾色和噪声都来自这些共用声明，显式引入而不依赖间接包含。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"

// --- 下界氛围色：按方向噪声在几种下界生物群系颜色之间过渡 ---
// 为什么用方向而不是坐标：下界天空没有地面参照，按玩家看的方向混合，抬头低头就能看到不同群系的色调。
vec3 omniNetherColor(vec3 direction, float horizon) {
    vec3 d = omniNormalize(direction); // 方向先归一化，后面的噪声取样才对所有机器一致。
    float region = omniNoise(d * 3.0); // 3 倍频率让几个群系片区在视野里铺开，频率太低会糊成一片。
    vec3 tone = mix(vec3(0.99,0.34,0.10), vec3(0.60,0.77,1.00), smoothstep(0.20,0.40,region)); // 荒原暖橙过渡到灵魂沙谷冷蓝。
    tone = mix(tone, vec3(1.00,0.55,0.35), smoothstep(0.40,0.55,region)); // 接着混入绯红森林的红橙。
    tone = mix(tone, vec3(0.50,0.85,0.90), smoothstep(0.55,0.70,region)); // 再混入诡异森林的青蓝。
    tone = mix(tone, vec3(0.70,0.66,0.62), smoothstep(0.70,0.85,region)); // 最后混入玄武岩三角洲的灰。
    tone *= mix(1.0,0.6,horizon); // 地平线以下压暗，避免向下看比抬头还亮。
    return tone * (0.5+0.5*horizon) * 0.5; // 再乘系数让亮度与加载器雾色同量级，替换后不突兀。
}

// --- 星点：把球面方向切成细格，只点亮极少数格子，得到稳定的星空 ---
// 为什么按方位角和仰角切格：每颗星钉死在方向上，相机转头时星空跟着转，不像贴屏纹理那样滑动。
// 为什么极点要保护：正上方和正下方没有方位角，`atan` 会算出 NaN 污染整幅画面。
float omniStars(vec3 direction) {
    float azimuth = (direction.x == 0.0 && direction.z == 0.0) ? 0.0 : atan(direction.z, direction.x); // 极点退化时取零，避免 NaN 传播。
    vec2 cell = floor(vec2(azimuth, asin(clamp(direction.y,-1.0,1.0))) * 700.0); // 700 让格子足够细，星星才像点而不是块。
    float density = step(0.998, omniHash(cell)); // 阈值很高，只有千分之二左右的格子亮。
    return density * pow(omniHash(cell + 3.1), 3.0); // 立方压低亮度，让多数星暗、少数星亮。
}

// --- 天空：把方向映射成颜色，昼夜、日落、日月圆盘、星空、雨天和维度底色都在这合成 ---
// 调用位置：effects/fog.glsl、effects/reflection.glsl；示例：`vec3 sky = omniSky(worldDirection);`
vec3 omniSky(vec3 direction) {
    vec3 d = omniNormalize(direction); // 归一化后方向才能直接和天体方向做点积。
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse) * sunPosition); // 转回世界空间，相机转头太阳不跟着动。
    vec3 moon = omniNormalize(mat3(gbufferModelViewInverse) * moonPosition); // 月亮用加载器给的真实方向。
    float day = smoothstep(-0.15, 0.1, sun.y); // 太阳高度在零点附近平滑过渡，昼夜不会硬切。
    float horizon = pow(1.0 - max(d.y, 0.0), 4.0); // 越靠近地平线值越大，用来提亮天际。
    vec3 nightSky = vec3(0.008,0.014,0.033); // 夜空底色，偏蓝的深色。
    vec3 daySky = mix(vec3(0.10,0.28,0.62), vec3(0.62,0.72,0.82), horizon); // 天顶偏蓝、地平线泛白。
    vec3 color = mix(nightSky, daySky, day); // 按昼夜权重插值，天空整天连续变化。
    float sunset = (1.0 - smoothstep(0.0,0.3,abs(sun.y))) * pow(max(dot(d,sun),0.0),8.0); // 只在太阳低且靠近太阳方向时出现，避免全天泛红。
    color += vec3(0.8,0.22,0.06) * sunset * horizon; // 暖色染在地平线一带。
    color += vec3(12.0,9.0,5.0) * smoothstep(0.9995,0.9998,dot(d,sun)) * day; // 太阳圆盘：点积极接近 1 才点亮，只占很小一块。
    color += vec3(0.6,0.7,1.0) * smoothstep(0.9993,0.9997,dot(d,moon)) * (1.0-day); // 月亮圆盘同理，只在夜里出现。
    float stars = omniStars(d); // 稳定的星点亮度，还没乘强度和时间。
    color += stars * OMNI_STAR_STRENGTH * (1.0-day) * smoothstep(0.0,0.2,d.y); // 白天和地平线附近隐藏，避免星星压过日光。
    color = mix(color, mix(vec3(0.025),vec3(0.22,0.25,0.29),day), rainStrength * 0.85); // 雨天按权重换成灰色阴天。
#ifdef OMNI_NETHER
#if OMNI_NETHER_COLOR == 1
    color = omniNetherColor(d,horizon); // 开启选项时用程序化下界氛围色。
#else
    color = omniLinear(fogColor) * (0.5 + 0.5 * horizon); // 关闭选项时退回加载器雾色，作为基础路径。
#endif
#elif defined OMNI_END
    color = vec3(0.018,0.008,0.034) + vec3(0.06,0.025,0.1) * omniNoise(d * 12.0); // 末地紫黑星云：底色加低频噪声。
    color += stars * 0.3 * OMNI_STAR_STRENGTH; // 末地保留稀疏星空，但不加昼夜因子。
#endif
    return mix(vec3(omniLuminance(color)), color, OMNI_SKY_SATURATION); // 按选项在灰度和原色之间插值，改天空饱和度。
}
#endif
