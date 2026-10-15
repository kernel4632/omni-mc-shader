/*
天空：算出主世界的昼夜天空、星空，以及下界和末地的环境底色，供背景画面和屏幕外反射共用。

调用位置：effects/fog.glsl 与 effects/reflection.glsl 调用，经 atmosphere.glsl、cloud.glsl 汇入 rendering/lighting.glsl 的背景绘制。
可复制示例（`worldDirection` 与 `ray` 都是世界空间方向）：
    `vec3 sky = omniSky(worldDirection);`                              背景天空颜色。
    `vec3 reflected = omniSky(mat3(gbufferModelViewInverse) * ray);`   屏幕外反射采样同一片天空。

设计原因：天空是"方向到颜色"的纯函数，只吃一个世界方向，所以背景、反射和雾能用同一个方向调它，各自不用重复判断昼夜。
算法来源：主世界天空按公开的 `Bruneton` 大气散射模型独立实现，公式与常数取自论文 `Precomputed Atmospheric Scattering`；
    不复制任何参考光影的源码，也不引入预计算查找表，而是沿视线数值积分出透过率、单次散射、太阳方向透过率与多次散射近似。
取舍：怎么把颜色画到屏幕由调用方决定，这里不出图也不读深度；代价是每个调用点都得给出正确的世界方向。
*/
#ifndef OMNI_SKY
#define OMNI_SKY
// @effect {"label":{"zh_cn":"天空","en_us":"Sky"}}
// @option {"label": {"zh_cn": "太阳亮度", "en_us": "Sun brightness"}, "slider": true, "description": {"zh_cn": "太阳圆盘有多亮。", "en_us": "How bright the sun disc is."}}
#define OMNI_SUN_DISK 1.0 // [0.0 0.5 1.0 1.5]
// @option {"label": {"zh_cn": "太阳大小", "en_us": "Sun size"}, "slider": true, "description": {"zh_cn": "太阳圆盘多大。", "en_us": "How large the sun disc is."}}
#define OMNI_SUN_SIZE 1.0 // [0.5 1.0 1.5 2.0]
// @option {"label": {"zh_cn": "月亮亮度", "en_us": "Moon brightness"}, "slider": true, "description": {"zh_cn": "月亮圆盘有多亮。", "en_us": "How bright the moon disc is."}}
#define OMNI_MOON_DISK 1.0 // [0.0 0.5 1.0 1.5]
// @option {"label": {"zh_cn": "月亮大小", "en_us": "Moon size"}, "slider": true, "description": {"zh_cn": "月亮圆盘多大。", "en_us": "How large the moon disc is."}}
#define OMNI_MOON_SIZE 1.0 // [0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"日月色温","en_us":"Sun/moon tint"},"description":{"zh_cn":"正值日月偏暖、负值偏冷；取零保持中性。","en_us":"Positive warms the sun and moon, negative cools them; zero keeps them neutral."},"slider":true}
#define OMNI_CELESTIAL_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label": {"zh_cn": "星星亮度", "en_us": "Star brightness"}, "slider": true, "description": {"zh_cn": "夜空星星多亮。", "en_us": "How bright the stars are."}}
#define OMNI_STAR_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"星星数量","en_us":"Star amount"},"description":{"zh_cn":"夜里星星多还是少。","en_us":"How many stars appear at night."},"slider":true}
#define OMNI_STAR_DENSITY 1.0 // [0.5 1.0 2.0 4.0]
// @option {"label": {"zh_cn": "日落强度", "en_us": "Sunset strength"}, "slider": true, "description": {"zh_cn": "日出日落时天边红霞多强。", "en_us": "How strong the sunset glow is."}}
#define OMNI_SUNSET_STRENGTH 1.0 // [0.0 0.5 1.0 1.5]
// @option {"label":{"zh_cn":"日落颜色","en_us":"Sunset color"},"description":{"zh_cn":"正值晚霞偏红、负值偏紫粉。","en_us":"Positive makes the sunset redder, negative makes it more purple-pink."},"slider":true}
#define OMNI_SUNSET_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label": {"zh_cn": "天空饱和度", "en_us": "Sky saturation"}, "slider": true, "description": {"zh_cn": "天空颜色鲜艳还是发灰。", "en_us": "Sky colour vividness."}}
#define OMNI_SKY_SATURATION 1.0 // [0.5 0.75 1.0 1.25]
// @option {"label": {"zh_cn": "天空整体亮度", "en_us": "Sky brightness"}, "slider": true, "description": {"zh_cn": "整个天空亮暗。", "en_us": "Overall sky brightness."}}
#define OMNI_SKY_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5]
// @option {"label": {"zh_cn": "下界程序化天空", "en_us": "Nether palette"}, "description": {"zh_cn": "用程序化混合替代固定下界雾色，覆盖荒原、灵魂沙谷、绯红与诡异森林和玄武岩。", "en_us": "Replaces a fixed nether fog colour with a procedural blend of nether biomes."}, "values": {"0": {"zh_cn": "固定雾色", "en_us": "Fixed fog colour"}, "1": {"zh_cn": "程序化", "en_us": "Procedural"}}}
#define OMNI_NETHER_COLOR 1 // [0 1]
// @option {"label": {"zh_cn": "末地天空亮度", "en_us": "End sky brightness"}, "slider": true, "description": {"zh_cn": "末地星空亮暗。", "en_us": "End sky brightness."}}
#define OMNI_END_SKY_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5]
// @option {"label":{"zh_cn":"使用资源包天空","en_us":"Resource-pack sky"},"description":{"zh_cn":"使用资源包自带的日月贴图，而不是内置的日月圆盘。","en_us":"Uses the resource pack's own sun and moon textures instead of the built-in discs."},"page":"world"}
//#define OMNI_RESOURCE_SKY
// @option {"label": {"zh_cn": "大气散射", "en_us": "Atmosphere scattering"}, "description": {"zh_cn": "是否用物理模型算天空；关掉退回简单渐变，作为基础路径。", "en_us": "Whether the sky uses the physical model; off falls back to a simple gradient."}, "values": {"0": {"zh_cn": "关", "en_us": "Off"}, "1": {"zh_cn": "开", "en_us": "On"}}}
#define OMNI_ATMOSPHERE_SCATTER 1 // [0 1]
// @option {"label": {"zh_cn": "散射强度", "en_us": "Scatter strength"}, "slider": true, "description": {"zh_cn": "大气散射整体亮暗，也能给天空加浓蓝色。", "en_us": "Overall strength of the atmosphere scattering and how deep the blue is."}}
#define OMNI_SCATTER_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label": {"zh_cn": "散射精细度", "en_us": "Scatter detail"}, "description": {"zh_cn": "沿视线的采样段数；越高越平滑也越耗性能。", "en_us": "Samples along the view; smoother but costlier."}, "values": {"8": {"zh_cn": "低", "en_us": "Low"}, "16": {"zh_cn": "中", "en_us": "Medium"}, "32": {"zh_cn": "高", "en_us": "High"}}}
#define OMNI_ATMOSPHERE_STEPS 16 // [8 16 32]
// @option {"label": {"zh_cn": "米氏方向性", "en_us": "Mie anisotropy"}, "slider": true, "description": {"zh_cn": "太阳附近光晕的集中程度，越大越亮越窄。", "en_us": "How tightly the sun halo concentrates; higher is brighter and narrower."}}
#define OMNI_ATMOSPHERE_MIE_G 0.8 // [0.0 0.5 0.8 0.95]
// @option {"label": {"zh_cn": "臭氧强度", "en_us": "Ozone strength"}, "slider": true, "description": {"zh_cn": "高空臭氧吸收多强，主要影响天顶的蓝。", "en_us": "How strong high-altitude ozone absorption is; mostly deepens the zenith blue."}}
#define OMNI_ATMOSPHERE_OZONE 1.0 // [0.0 1.0 2.0]
// @option {"label": {"zh_cn": "多次散射强度", "en_us": "Multiple scatter"}, "slider": true, "description": {"zh_cn": "多次散射近似有多强，补足只算一次散射时偏暗的天空。", "en_us": "Strength of the multiple scattering approximation that lifts a single-scatter sky."}}
#define OMNI_ATMOSPHERE_MULTIPLE 1.0 // [0.0 0.5 1.0 2.0]
// 天体、雾色和噪声都来自这些共用声明，显式引入而不依赖间接包含。
#include "/common/math.glsl"
#include "/common/uniforms.glsl"

// --- 大气常数：公开 `Bruneton` 预计算散射模型的取值，长度单位公里，亮度单位辐射亮度 ---
const float omniPi = 3.14159265358979; // 相位函数要用圆周率，单独列出避免到处写长小数。
const vec3 omniSolarIrradiance = vec3(1.68194,1.85149,1.91198); // 太阳辐照度，决定大气散射的基准亮度。
const float omniSunAngularRadius = 0.005; // 太阳视半径，日落时用它对太阳方向透过率做渐隐。
const float omniGroundRadius = 6360.0; // 行星底半径，越过它就算被地面挡住。
const float omniTopRadius = 6420.0; // 大气层顶半径，视线到这里就离开大气。
const vec3 omniRayleighScattering = vec3(0.008396,0.014590,0.033100); // 瑞利散射系数，蓝光最强，天空因此偏蓝。
const float omniMieScattering = 0.003996; // 米氏散射系数，气溶胶造成太阳附近的白晕。
const float omniMieExtinction = 0.004440; // 米氏消光系数，比散射略大，差额是被吸收的部分。
const vec3 omniOzoneAbsorption = vec3(0.0020031,0.0016555,0.0000847); // 臭氧吸收系数，主要吃掉蓝绿之外的长波。
const float omniGroundAlbedo = 0.1; // 地面反照率，多次散射近似里算一次地面反弹。
const float omniRayleighScaleHeight = 8.0; // 瑞利密度标高，越往上越稀，约八公里掉到三成七。
const float omniMieScaleHeight = 1.2; // 米氏密度标高，气溶胶集中在近地约一点二公里。
const float omniOzoneCenter = 25.0; // 臭氧层中心高度，约二十五公里。
const float omniOzoneHalfWidth = 15.0; // 臭氧层半宽，两侧到十与四十公里降到零。
const float omniIsotropicPhase = 0.0795774715; // 各向同性相函数 1/(4π)，多次散射的方向平均值。
const float omniSkyScale = 20.0; // 量级匹配：把物理辐射亮度缩到本项目天空的亮度口径，属未实机确认的取值。
const int omniSunSteps = 8; // 太阳方向透过率的固定段数；它对画面影响小，不再单独开选项。

// --- 大气几何：视线与两层球面在哪里相交 ---
// 到大气层顶的交点：解视线与顶球面的方程，取正根；相机在大气内部，这个根一定存在。
float omniDistanceToTop(float r, float mu) {
    float discriminant = r*r*(mu*mu-1.0) + omniTopRadius*omniTopRadius; // 交点判别式，小于零表示这条视线到不了层顶。
    return -r*mu + sqrt(max(discriminant,0.0)); // 取朝向层顶一侧的远交点。
}
// 视线是否打到地面：只有朝下、且与底球面相交时才被行星挡住。
bool omniRayHitsGround(float r, float mu) {
    return mu < 0.0 && r*r*(mu*mu-1.0) + omniGroundRadius*omniGroundRadius >= 0.0; // 朝上的方向永远不挡。
}
// --- 密度剖面：三种成分各自随高度变化 ---
// 指数密度：给定标高，高度越高密度越低，涨到标高处剩约三成七。
float omniExpDensity(float altitude, float scaleHeight) {
    return exp(-altitude/scaleHeight); // 单位公里的指数衰减。
}
// 臭氧密度：在约二十五公里最高的三角层，向上向下都变稀薄。
float omniOzoneDensity(float altitude) {
    return max(1.0 - abs(altitude-omniOzoneCenter)/omniOzoneHalfWidth, 0.0); // 三角剖面，层外归零。
}
// --- 相位函数：散射把光往哪个方向偏 ---
// 瑞利相位：前后基本对称，只在前后稍强，是蓝天的主要来源。
float omniRayleighPhase(float mu) {
    return 3.0/(16.0*omniPi)*(1.0 + mu*mu); // 公开模型的瑞利相位公式。
}
// 米氏相位：强烈偏向前方，太阳附近因此出现暖白光晕。
// 用公开模型的 `Cornette-Shanks` 形式，比只用 `Henyey-Greenstein` 更贴近真实米氏散射。
float omniMiePhase(float g, float mu) {
    float g2 = g*g; // 各向异性因子的平方，下面反复用到。
    float k = 3.0/(8.0*omniPi)*(1.0-g2)/(2.0+g2); // 归一化系数，保证整个球面的积分为一。
    return k*(1.0+mu*mu)/pow(1.0+g2-2.0*g*mu, 1.5); // 前向峰随 g 增大而更尖更亮。
}
// --- 太阳方向透过率：从采样点朝太阳走到层顶，累计被吸收和散射掉的能量 ---
// 为什么逐点计算：越靠近地平线，阳光穿过的空气越长、损失越多，黄昏的红色和天顶的蓝色都由它决定。
vec3 omniSunTransmittance(vec3 point, vec3 sunDirection) {
    float r = length(point); // 采样点到地心的距离。
    float mu = dot(point, sunDirection)/r; // 太阳方向与当地"向上"的夹角余弦。
    if (omniRayHitsGround(r, mu)) return vec3(0.0); // 太阳落到地平线以下时，这段光被行星完全挡住。
    float distance = omniDistanceToTop(r, mu); // 这段视线在大气中的长度。
    float stepLength = distance/float(omniSunSteps); // 每段长度，段数固定。
    vec3 depthRayleigh = vec3(0.0); // 累积的瑞利密度积分。
    float depthMie = 0.0; // 累积的米氏密度积分。
    float depthOzone = 0.0; // 累积的臭氧密度积分。
    for (int i=0;i<omniSunSteps;i++) { // 沿太阳方向分段取中点积分。
        vec3 samplePoint = point + sunDirection*(float(i)+0.5)*stepLength; // 当前采样点位置。
        float altitude = max(length(samplePoint)-omniGroundRadius, 0.0); // 采样点离地面的高度。
        depthRayleigh += omniExpDensity(altitude, omniRayleighScaleHeight)*stepLength; // 瑞利密度乘段长。
        depthMie += omniExpDensity(altitude, omniMieScaleHeight)*stepLength; // 米氏密度乘段长。
        depthOzone += omniOzoneDensity(altitude)*stepLength; // 臭氧密度乘段长。
    }
    vec3 opticalDepth = omniRayleighScattering*depthRayleigh // 瑞利消光。
                      + vec3(omniMieExtinction)*depthMie // 米氏消光。
                      + omniOzoneAbsorption*depthOzone*OMNI_ATMOSPHERE_OZONE; // 臭氧吸收；强度可调。
    float horizonFade = smoothstep(0.0, omniSunAngularRadius, mu); // 太阳刚滑到地平线时渐隐，避免颜色硬切。
    return exp(-opticalDepth)*horizonFade; // 透过率等于消光光学的负指数。
}
// --- 大气散射天空：沿视线把空气切成小段，逐段累加收到的阳光，得到这个方向的天空颜色 ---
// 为什么从地表出发：相机贴地，六十公里厚的大气里玩家海拔可忽略，固定在底半径让结果只和方向有关。
// 为什么朝下的视线要压平：看向地面的方向穿不过整层大气，用水平方向代替，避免雾在地面下方发黑。
vec3 omniAtmosphereSky(vec3 direction, vec3 sunDirection) {
    vec3 ray = direction; // 先复制一份，下面可能把朝下的方向压平。
    if (ray.y < 0.0) { // 只有朝下的方向需要处理。
        vec2 level = ray.xz; // 取水平投影。
        ray = length(level) > 1e-6 ? omniNormalize(vec3(level.x,0.0,level.y)) : vec3(1.0,0.0,0.0); // 退化为正下方时用一个水平方向兜底。
    }
    float r = omniGroundRadius; // 相机半径取底半径。
    float mu = dot(ray, vec3(0.0,1.0,0.0)); // 视线与向上的夹角余弦。
    float sunMu = dot(ray, sunDirection); // 视线与太阳的夹角余弦，决定相位函数。
    float distance = omniDistanceToTop(r, mu); // 视线在大气中的长度。
    float stepLength = distance/float(OMNI_ATMOSPHERE_STEPS); // 每段长度，段数可调。
    float phaseRayleigh = omniRayleighPhase(sunMu); // 瑞利相位。
    float phaseMie = omniMiePhase(OMNI_ATMOSPHERE_MIE_G, sunMu); // 米氏相位；方向性可调。
    vec3 depthRayleigh = vec3(0.0); // 相机到当前采样点的瑞利密度积分。
    float depthMie = 0.0; // 相机到当前采样点的米氏密度积分。
    float depthOzone = 0.0; // 相机到当前采样点的臭氧密度积分。
    vec3 single = vec3(0.0); // 单次散射的累加结果。
    vec3 multiple = vec3(0.0); // 多次散射近似里与方向无关的那一项。
    for (int i=0;i<OMNI_ATMOSPHERE_STEPS;i++) { // 沿视线分段取中点积分；段数可调。
        float t = (float(i)+0.5)*stepLength; // 当前段中点距相机的距离。
        vec3 point = vec3(0.0,r,0.0) + ray*t; // 采样点位置，相机放在中轴上方。
        float altitude = max(length(point)-omniGroundRadius, 0.0); // 采样点离地面的高度。
        float densityRayleigh = omniExpDensity(altitude, omniRayleighScaleHeight); // 当地瑞利密度。
        float densityMie = omniExpDensity(altitude, omniMieScaleHeight); // 当地米氏密度。
        float densityOzone = omniOzoneDensity(altitude); // 当地臭氧密度。
        depthRayleigh += densityRayleigh*stepLength; // 累加瑞利密度。
        depthMie += densityMie*stepLength; // 累加米氏密度。
        depthOzone += densityOzone*stepLength; // 累加臭氧密度。
        vec3 viewOptical = omniRayleighScattering*depthRayleigh // 视线消光：瑞利。
                         + vec3(omniMieExtinction)*depthMie // 视线消光：米氏。
                         + omniOzoneAbsorption*depthOzone*OMNI_ATMOSPHERE_OZONE; // 视线消光：臭氧；强度可调。
        vec3 viewTransmittance = exp(-viewOptical); // 相机到采样点的透过率。
        vec3 sunTransmittance = omniSunTransmittance(point, sunDirection); // 采样点到太阳的透过率。
        vec3 rayleighLight = omniRayleighScattering*densityRayleigh*phaseRayleigh; // 瑞利单次散射。
        vec3 mieLight = vec3(omniMieScattering)*densityMie*phaseMie; // 米氏单次散射。
        single += (rayleighLight+mieLight)*sunTransmittance*viewTransmittance*stepLength; // 这段贡献给单次散射。
        multiple += (omniRayleighScattering*densityRayleigh + vec3(omniMieScattering)*densityMie)*sunTransmittance*viewTransmittance*stepLength; // 多次散射用与方向无关的相位。
    }
    float multipleFactor = omniIsotropicPhase*(1.0+omniGroundAlbedo)*OMNI_ATMOSPHERE_MULTIPLE; // 各向同性平均相位，再算一次地面反弹；强度可调。
    vec3 radiance = (single + multiple*multipleFactor)*omniSolarIrradiance; // 乘太阳辐照度得到辐射亮度。
    return radiance*omniSkyScale*OMNI_SCATTER_STRENGTH; // 缩放到本项目天空口径；散射强度可调。
}

// --- 下界氛围色：按方向噪声在几种下界生物群系颜色之间过渡 ---
// 为什么用方向而不是坐标：下界天空没有地面参照，按玩家看的方向混合，抬头低头就能看到不同群系的色调。
vec3 omniNetherColor(vec3 direction, float horizon) {
    vec3 d = omniNormalize(direction); // 方向先归一化，后面的噪声取样才对所有机器一致。
    float region = omniNoise(d * 3.0); // 3 倍频率让几个群系片区在视野里铺开，频率太低会糊成一片。
    vec3 tone = mix(vec3(0.99,0.34,0.10), vec3(0.60,0.77,1.00), smoothstep(0.20,0.40,region)); // 荒原暖橙过渡到灵魂沙谷冷蓝。
    tone = mix(tone, vec3(1.00,0.55,0.35), smoothstep(0.40,0.55,region)); // 接着混入绯红森林的红橙。
    tone = mix(tone, vec3(0.50,0.85,0.90), smoothstep(0.55,0.70,region)); // 再混入诡异森林的青蓝。
    tone = mix(tone, vec3(0.70,0.66,0.62), smoothstep(0.70,0.85,region)); // 最后混入玄武岩三角洲的灰。
    tone *= mix(1.0,0.6,horizon); // 地平线以下（`horizon` 变大）先压一档，避免向下看比抬头还亮。
    return tone * (1.0-0.5*horizon) * 0.5; // 地平线以下再压一档，整体缩到与加载器雾色同量级，替换后不突兀。
}

// --- 星点：把球面方向切成细格，只点亮少数格子，得到稳定的星空 ---
// 为什么按方位角和仰角切格：每颗星钉死在方向上，相机转头时星空跟着转，不像贴屏纹理那样滑动。
// 为什么极点要保护：正上方和正下方没有方位角，`atan` 会算出 NaN 污染整幅画面。
float omniStars(vec3 direction) {
    float azimuth = (direction.x == 0.0 && direction.z == 0.0) ? 0.0 : atan(direction.z, direction.x); // 极点退化时取零，避免 NaN 传播。
    vec2 cell = floor(vec2(azimuth, asin(clamp(direction.y,-1.0,1.0))) * 700.0); // 700 让格子足够细，星星才像点而不是块。
    float cut = 0.999 - 0.001 * OMNI_STAR_DENSITY; // 数量选项越高阈值越低，亮格越多；默认一约等于千分之二。
    float density = step(cut, omniHash(cell)); // 只有超过阈值的少量格子亮。
    return density * pow(omniHash(cell + 3.1), 3.0); // 立方压低亮度，让多数星暗、少数星亮。
}

// --- 天空：把方向映射成颜色，昼夜、日落、日月圆盘、星空、雨天和维度底色都在这合成 ---
// 调用位置：effects/fog.glsl、effects/reflection.glsl；示例：`vec3 sky = omniSky(worldDirection);`
vec3 omniSky(vec3 direction) {
    vec3 d = omniNormalize(direction); // 归一化后方向才能直接和天体方向做点积。
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse) * sunPosition); // 转回世界空间，相机转头太阳不跟着动。
    vec3 moon = omniNormalize(mat3(gbufferModelViewInverse) * moonPosition); // 月亮用加载器给的真实方向。
    vec3 celestialTint = exp(vec3(0.25,0.0,-0.25)*OMNI_CELESTIAL_TINT); // 日月色温：正值加红减蓝、负值相反，取零为全一。
    float day = smoothstep(-0.15, 0.1, sun.y); // 太阳高度在零点附近平滑过渡，昼夜不会硬切。
    float horizon = pow(1.0 - max(d.y, 0.0), 4.0); // 越靠近地平线值越大，用来提亮天际。
    vec3 nightSky = vec3(0.008,0.014,0.033); // 夜空底色，偏蓝的深色。
    vec3 color; // 天空底色，下面按散射开关在物理模型和简单渐变之间取一个。
#if OMNI_ATMOSPHERE_SCATTER == 1
    color = omniAtmosphereSky(d,sun); // 主世界的天空用物理大气散射模型算出来。
    color += nightSky*(1.0-day); // 夜晚补一层深蓝底，避免天空全黑，也给星星一个背景。
#else
    vec3 daySky = mix(vec3(0.10,0.28,0.62), vec3(0.62,0.72,0.82), horizon); // 关闭散射时退回简单渐变：天顶偏蓝、地平线泛白。
    color = mix(nightSky, daySky, day); // 按昼夜权重插值，天空整天连续变化。
#endif
    float sunset = (1.0 - smoothstep(0.0,0.3,abs(sun.y))) * pow(max(dot(d,sun),0.0),8.0); // 只在太阳低且靠近太阳方向时出现，避免全天泛红。
    vec3 sunsetColor = vec3(0.8,0.22,0.06)*exp(vec3(0.3,0.0,-0.3)*OMNI_SUNSET_TINT); // 日落颜色：正值偏红、负值偏紫粉。
    color += sunsetColor * sunset * horizon * OMNI_SUNSET_STRENGTH; // 暖色染在地平线一带，强度可调。
#ifndef OMNI_RESOURCE_SKY
    float sunRadius = 0.0002*OMNI_SUN_SIZE; // 太阳圆盘的角半径；大小一约等于原阈值。
    color += vec3(12.0,9.0,5.0)*celestialTint * smoothstep(1.0-sunRadius*2.0,1.0-sunRadius,dot(d,sun)) * day * OMNI_SUN_DISK; // 太阳圆盘：越接近太阳方向越亮；大小与亮度可调。
    float moonRadius = 0.0003*OMNI_MOON_SIZE; // 月亮圆盘的角半径；大小一约等于原阈值。
    color += vec3(0.6,0.7,1.0)*celestialTint * smoothstep(1.0-moonRadius*2.0,1.0-moonRadius,dot(d,moon)) * (1.0-day) * OMNI_MOON_DISK; // 月亮圆盘同理，只在夜里出现。
#endif
    float stars = omniStars(d); // 稳定的星点亮度，还没乘强度和时间。
    color += stars * OMNI_STAR_STRENGTH * (1.0-day) * smoothstep(0.0,0.2,d.y); // 白天和地平线附近隐藏，避免星星压过日光。
    color = mix(color, mix(vec3(0.025),vec3(0.22,0.25,0.29),day), rainStrength * 0.85); // 雨天按权重换成灰色阴天。
    color *= OMNI_SKY_BRIGHTNESS; // 天空整体亮度，只作用主世界天空；下界与末地底色不读它。
#ifdef OMNI_NETHER
#if OMNI_NETHER_COLOR == 1
    color = omniNetherColor(d,horizon); // 开启选项时用程序化下界氛围色。
#else
    color = omniLinear(fogColor) * (0.5 + 0.5 * horizon); // 关闭选项时退回加载器雾色，作为基础路径。
#endif
#elif defined OMNI_END
    color = (vec3(0.018,0.008,0.034) + vec3(0.06,0.025,0.1) * omniNoise(d * 12.0)) * OMNI_END_SKY_BRIGHTNESS; // 末地紫黑星云：底色加低频噪声，亮度可调。
    color += stars * 0.3 * OMNI_STAR_STRENGTH; // 末地保留稀疏星空，但不加昼夜因子。
#endif
    return mix(vec3(omniLuminance(color)), color, OMNI_SKY_SATURATION); // 按选项在灰度和原色之间插值，改天空饱和度。
}
#endif
