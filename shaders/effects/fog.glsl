// 雾：负责合成阶段的空气效果——距离雾、高度雾、水下吸收和体积散射，是画面空气感的最后一层。
// 调用位置：rendering/composite.glsl 的 omniSurfaceAir 在云之后调用，经各维度 composite.fsh 进入游戏。
// 可复制示例：`vec3 fogged = omniFog(color, view, world);` 其中 `color` 为当前颜色，`view` 为相机相对视空间位置，`world` 为相机相对世界位置。
// 设计原因：空气色取自 omniSky，让雾与天空同色，避免天地出现两种颜色；水下单独做分波段吸收，因为水对红绿蓝衰减快慢不同；
//   末地不用加载器雾色，改用紫色漩涡叠加虚空暗色，免得和末地天空打架；体积光一律沿世界空间取样，保证光柱不随相机滑动。
#ifndef OMNI_FOG
#define OMNI_FOG
// @effect {"label":{"zh_cn":"雾与空气","en_us":"Fog"}}
// @option {"label":{"zh_cn":"雾开关","en_us":"Fog"},"description":{"zh_cn":"远处有没有空气雾；关掉后只保留水下效果。","en_us":"Whether distance and height fog appear; off keeps only the underwater effect."}}
#define OMNI_FOG_ENABLED
// @option {"label": {"zh_cn": "雾浓度", "en_us": "Fog density"}, "slider": true, "description": {"zh_cn": "雾浓还是淡，看得多远。", "en_us": "Fog thickness and view distance."}}
#define OMNI_FOG_DENSITY 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"雾颜色","en_us":"Fog tint"},"description":{"zh_cn":"雾偏暖还是偏冷；取零与天空同色。","en_us":"Warms or cools the fog; zero matches the sky."},"slider":true}
#define OMNI_FOG_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"高度雾开关","en_us":"Height fog"},"description":{"zh_cn":"低处更浓的一层雾；关掉只剩距离雾。","en_us":"Extra fog that thickens lower down; off leaves only distance fog."}}
#define OMNI_HEIGHT_FOG_ENABLED
// @option {"label": {"zh_cn": "高度雾浓度", "en_us": "Height fog density"}, "slider": true, "description": {"zh_cn": "低处雾多浓。", "en_us": "How thick the fog is near the ground."}}
#define OMNI_HEIGHT_FOG 0.5 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"高度雾起始高度","en_us":"Height fog base"},"description":{"zh_cn":"低于此高度雾更浓，用来贴合海平面；单位世界格。","en_us":"Below this altitude fog thickens; measured in world blocks."}}
#define OMNI_FOG_HEIGHT 64.0 // [0.0 32.0 64.0 96.0 128.0]
// @option {"label": {"zh_cn": "高度雾衰减", "en_us": "Height fog falloff"}, "slider": true, "description": {"zh_cn": "高度雾随高度衰减多快。", "en_us": "How fast height fog fades with altitude."}}
#define OMNI_FOG_SCALE 0.035 // [0.01 0.02 0.035 0.06]
// @option {"label": {"zh_cn": "体积光开关", "en_us": "Volumetric light"}, "description": {"zh_cn": "阳光有没有穿过空气的光柱。", "en_us": "Whether sunlight shows as light shafts."}}
//#define OMNI_VOLUMETRIC_LIGHT
// @option {"label": {"zh_cn": "阳光光柱强度", "en_us": "Sun shaft strength"}, "slider": true, "description": {"zh_cn": "光柱多亮。", "en_us": "How bright the light shafts are."}}
#define OMNI_VOLUMETRIC_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label": {"zh_cn": "水下光柱强度", "en_us": "Underwater shaft strength"}, "slider": true, "description": {"zh_cn": "水下光柱多亮。", "en_us": "How bright the underwater shafts are."}}
#define OMNI_UNDERWATER_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label": {"zh_cn": "光柱精细度", "en_us": "Shaft detail"}, "description": {"zh_cn": "光柱沿视线的采样段数；越多越平滑也越耗性能。", "en_us": "Samples along the view for the shafts; smoother but costlier."}, "values": {"8": {"zh_cn": "低", "en_us": "Low"}, "12": {"zh_cn": "中", "en_us": "Medium"}, "16": {"zh_cn": "高", "en_us": "High"}}}
#define OMNI_VFOG_STEPS 12 // [8 12 16]
// @option {"label": {"zh_cn": "水下雾开关", "en_us": "Underwater fog"}, "description": {"zh_cn": "水下沿视线步进阴影可见性生成蓝色光柱。", "en_us": "Marches shadow visibility underwater to draw blue light shafts."}, "values": {"0": {"zh_cn": "关", "en_us": "Off"}, "1": {"zh_cn": "开", "en_us": "On"}}}
#define OMNI_UNDERWATER_FOG 1 // [0 1]
// @option {"label": {"zh_cn": "水下雾浓度", "en_us": "Underwater fog density"}, "slider": true, "description": {"zh_cn": "水里能看多远。", "en_us": "How far you can see underwater."}}
#define OMNI_UNDERWATER_DENSITY 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"水下颜色","en_us":"Underwater tint"},"description":{"zh_cn":"水下偏青绿还是偏蓝；取零保持默认。","en_us":"Underwater leans green or blue; zero keeps the default."},"slider":true}
#define OMNI_UNDERWATER_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label": {"zh_cn": "末地雾开关", "en_us": "End fog"}, "description": {"zh_cn": "末地紫色漩涡雾叠加虚空暗色，替代单纯天空色。", "en_us": "Adds purple end haze with void darkening instead of a plain sky colour."}, "values": {"0": {"zh_cn": "关", "en_us": "Off"}, "1": {"zh_cn": "开", "en_us": "On"}}}
#define OMNI_END_FOG 1 // [0 1]
// @option {"label": {"zh_cn": "末地雾浓度", "en_us": "End fog density"}, "slider": true, "description": {"zh_cn": "末地紫雾多浓。", "en_us": "How thick the End fog is."}}
#define OMNI_END_FOG_DENSITY 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label": {"zh_cn": "下界雾浓度", "en_us": "Nether fog density"}, "slider": true, "description": {"zh_cn": "下界空气多浑浊。", "en_us": "How murky the Nether air is."}}
#define OMNI_NETHER_FOG_DENSITY 1.0 // [0.0 0.5 1.0 2.0]
// 阴影图提供空气是否受光的依据。
#include "/effects/shadow.glsl"
#include "/effects/sky.glsl"
// 雾直接使用归一化、线性色与噪声，显式声明依赖而不依赖间接引用。
#include "/common/math.glsl"
// 远景雾衔接读取远景相关的选项。
#include "/effects/world.glsl"
// 水下吸收与水面合成共用同一份光学常数，所以引用水效果主体，避免两处各写一套数值。
#include "/effects/water.glsl"
// 非负取零：`float` 的 `max(NaN,0.0)` 结果由显卡决定，用比较写法保证 NaN 也回退为 0，避免污染整幅画面。
// 只服务本文件，所以留在原地；深度重建等边界数据先经过它，再参与后面的指数计算。
float omniNonNegative(float value) { return value >= 0.0 ? value : 0.0; }
// 末地雾：紫色漩涡雾叠加底部虚空暗色，按绝对位置和高度变化，替代单纯的天空色。
// 为什么用绝对位置：`world` 是相机相对坐标，直接拿它做噪声会随相机平移滑动，加上 cameraPosition 后雾团固定在世界里。
vec3 omniEndFog(vec3 world) {
    vec3 p = world+cameraPosition; // 转成绝对位置，雾团稳定不随相机滑动。
    float swirl = omniNoise(p*0.004+vec3(frameTimeCounter*0.01)); // 缓慢移动的噪声团，给出漩涡感。
    float height = smoothstep(-40.0,20.0,p.y); // 按高度分地面与虚空，低处属于虚空。
    vec3 haze = mix(vec3(0.02,0.01,0.05),vec3(0.32,0.16,0.45),swirl); // 深紫到亮紫随噪声混合。
    return mix(haze,vec3(0.10,0.04,0.16),1.0-height); // 越靠低处越暗，表现虚空。
}
// 水下光柱：算出这条视线在水下收到的蓝色光柱颜色，关闭或非主世界时为零。
// 为什么只在近处累积：光柱来自岸边和头顶的缝隙，设 40 米上限可以省掉远处的噪声和无意义开销。
vec3 omniUnderwaterShafts(vec3 view, vec3 world, float distance) {
#if OMNI_UNDERWATER_FOG == 1 && !defined OMNI_NETHER && !defined OMNI_END
    float shaftRange = min(distance,40.0); // 只在近岸短距离累积光柱。
    vec3 sampleNormal = omniNormalize(mat3(gbufferModelView)*vec3(0.0,1.0,0.0)); // 阴影接口接收视空间法线，整条视线共用向上法线。
    float shaft = 0.0; // 沿视线累计的阴影可见性，一为全亮，零为全遮挡。
    for (int i=0;i<8;i++) { // 八段等距中点积分，兼顾开销和平滑。
        float t = (float(i)+0.5)/8.0; // 当前采样点在视线上的归一化位置。
        vec3 sampleWorld = world*t; // 转到世界空间取候选点，阴影图按世界位置比较。
        shaft += omniShadow(sampleWorld,sampleNormal)*(1.0-t); // 近处权重更高，远处的可见性贡献更小。
    }
    shaft /= 8.0; // 取平均得到归一化可见性。
    vec3 light = omniNormalize(shadowLightPosition); // 当前主光源方向，决定光柱朝向。
    float phase = 0.1 + pow(max(dot(omniNormalize(view),light),0.0),8.0); // 正向面对光源时更亮，强调天体方向。
    return vec3(0.05,0.22,0.32)*shaft*phase*(1.0-exp(-shaftRange*0.1))*OMNI_UNDERWATER_STRENGTH; // 蓝色光柱强度随可见性、相位和近处距离变化；强度可调。
#else
    return vec3(0.0); // 关闭选项或非主世界时不加光柱。
#endif
}
// 体积光：算出这条视线收到的阳光光柱颜色，下界与末地不参与。
// 为什么乘 fogAmount：雾越厚光柱越明显，用最终混合权重缩放能让光柱和雾保持一致。
vec3 omniVolumetricLight(vec3 view, vec3 world, float distance, float density, float fogAmount) {
#if defined OMNI_VOLUMETRIC_LIGHT && !defined OMNI_NETHER && !defined OMNI_END
    vec3 sampleNormal = omniNormalize(mat3(gbufferModelView)*vec3(0.0,1.0,0.0)); // 阴影接口接收视空间法线，整条视线共用向上法线。
    float scattering = 0.0; // 沿视线累计的、带上雾权重的阴影可见性。
    for (int i=0;i<OMNI_VFOG_STEPS;i++) { // 步数可调，越多越平滑也越耗性能。
        float t = (float(i)+0.5)/float(OMNI_VFOG_STEPS); // 当前采样点在视线上的归一化位置。
        vec3 sampleWorld = world*t; // 转到世界空间取候选点，阴影图按世界位置比较。
        scattering += omniShadow(sampleWorld, sampleNormal) * exp(-density*distance*t); // 越远处空气越厚，可见性权重越低。
    }
    vec3 light = omniNormalize(shadowLightPosition); // 当前主光源方向。
    float phase = 0.04 + pow(max(dot(omniNormalize(view),light),0.0),8.0); // 正向面对光源时更亮，强调天体方向。
    return vec3(0.75,0.68,0.5)*scattering/float(OMNI_VFOG_STEPS)*fogAmount*phase*OMNI_VOLUMETRIC_STRENGTH; // 暖白阳光光柱，强度受雾量、相位与强度选项控制。
#else
    return vec3(0.0); // 关闭选项或非主世界时不加光柱。
#endif
}
// 雾主体：先算出距离、密度和空气色，再按水下、主世界、下界、末地分别合成。
vec3 omniFog(vec3 color, vec3 view, vec3 world) {
    float distance = omniNonNegative(length(view)); // 边界数据：深度重建异常给出 NaN 或负值时先归零。
    distance = min(distance,32000.0); // 背景重建可能给出超大距离，截断避免指数运算溢出。
    float density = 0.0; // 空气雾密度；关闭雾开关时保持为零。
#ifdef OMNI_FOG_ENABLED
    density = (0.0015 + rainStrength * 0.004) * OMNI_FOG_DENSITY; // 基础密度，雨天更浓以缩短能见度。
#ifdef OMNI_HEIGHT_FOG_ENABLED
    density += exp(-max(cameraPosition.y + world.y * 0.5 - OMNI_FOG_HEIGHT,-40.0)*OMNI_FOG_SCALE) * 0.001 * OMNI_HEIGHT_FOG; // 用视线中点高度近似，低于起始高度越浓；起始高度与衰减都可调。
#endif
#endif
    density = omniNonNegative(density); // 保证密度非负，避免负指数把雾算成负值。
    vec3 atmosphere = omniSky(omniNormalize(world)); // 默认空气色与天空一致，天地不脱节。
    atmosphere *= vec3(1.0+0.25*OMNI_FOG_TINT,1.0,1.0-0.25*OMNI_FOG_TINT); // 雾颜色：正值偏暖、负值偏冷，取零与天空同色。
#ifdef OMNI_NETHER
    density *= 4.0*OMNI_NETHER_FOG_DENSITY; // 下界空气厚重，整体加浓，并可再调。
    atmosphere = omniLinear(fogColor); // 下界保留加载器给出的生物群系雾色。
#elif defined OMNI_END
#if OMNI_END_FOG == 1
    atmosphere = omniEndFog(world); // 末地紫雾叠加虚空暗色。
    density *= 1.5*OMNI_END_FOG_DENSITY; // 末地雾更浓，并可再调。
#else
    atmosphere = omniSky(omniNormalize(world)); // 关闭时只用自定义环境色，不引入太阳光柱。
#endif
#endif
    float fogAmount = 1.0-exp(-density*distance); // 消光与散射共同的混合权重，随距离趋向一。
#ifdef DISTANT_HORIZONS
    fogAmount = mix(fogAmount,max(fogAmount,smoothstep(0.6,1.0,clamp(distance/256.0,0.0,1.0))),OMNI_DH_FOG_BLEND); // 远景雾衔接：很远处额外补雾，抹平近远景交界的雾差；取零保持原状。
#endif
    if (isEyeInWater == 1) { // 水下单独处理，分波段吸收后不再叠加空气距离雾。
        vec3 water = omniWaterTransmit(color,distance*OMNI_UNDERWATER_DENSITY); // 与水面合成共用同一份吸收与散射常数；浓度选项再乘距离。
        water *= vec3(1.0+0.25*OMNI_UNDERWATER_TINT,1.0,1.0-0.25*OMNI_UNDERWATER_TINT); // 水下颜色：正值偏暖、负值偏冷，取零保持默认。
        water += omniUnderwaterShafts(view,world,distance); // 叠加水下体积光柱。
        return water; // 提前返回，水下不参与后面的空气雾与体积光。
    }
    color += omniVolumetricLight(view,world,distance,density,fogAmount); // 主世界叠加上阳光体积光柱。
    return mix(color,atmosphere,fogAmount); // 消光后的场景色与空气色按权重混合。
}
#endif
