/*
云：给天空画云，并让地表的直射光按云密度变暗。体积云与云影共享同一份密度。

在什么位置被调用：
  rendering/composite.glsl 用 omniCloud 把云叠到天空上，挡在地形之后。
  rendering/lighting.glsl 在天空背景里先算天空色，再叠云与氛围。
  effects/sunlight.glsl 用 omniCloudShadow 让地表直射光按云层变暗。

可直接复制的最小示例：
  `vec3 天空 = omniCloud(omniSky(方向), 方向, 32000.0);`
  `float 阳光 = omniCloudShadow(世界坐标);`

关键设计原因与取舍：
  只保留一套体积云：不再让玩家在单层/体积/平面之间选。云块由三维噪声加云层高度区间步进得到，
  形状、颜色、云影都从同一份密度出发，所以眼见的云和地上的云影对得上。
  采样步数做成「云精细度」选项，玩家在更细致和更省性能之间自己取舍。
  下界和末地没有真实大气，本文件直接返回原色，交给各自的天空处理。
*/
#ifndef OMNI_CLOUD
#define OMNI_CLOUD
// @effect {"label":{"zh_cn":"云","en_us":"Clouds"}}
// @option {"label":{"zh_cn":"云量","en_us":"Cloud amount"},"description":{"zh_cn":"天上有多少云；调高云更满更连片，取零就没有云。","en_us":"How much cloud covers the sky; higher is fuller, zero means no clouds."},"slider":true}
#define OMNI_CLOUD_COVERAGE 0.5 // [0.0 0.25 0.5 0.75 1.0]
// @option {"label":{"zh_cn":"云高度","en_us":"Cloud height"}}
#define OMNI_CLOUD_HEIGHT 192.0 // [128.0 192.0 256.0 320.0]
// @option {"label":{"zh_cn":"云厚度","en_us":"Cloud thickness"},"description":{"zh_cn":"云层有多厚；也决定云影要穿过多少云。","en_us":"How thick the cloud layer is; also the depth the cloud shadow marches."}}
#define OMNI_CLOUD_THICKNESS 32.0 // [16.0 32.0 64.0 128.0]
// @option {"label":{"zh_cn":"云块大小","en_us":"Cloud size"},"description":{"zh_cn":"大于一云块更小更碎，小于一云块更大更整。","en_us":"Above one makes smaller broken clouds, below one makes larger solid clouds."},"slider":true}
#define OMNI_CLOUD_SCALE 1.0 // [0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"云速","en_us":"Cloud speed"},"slider":true}
#define OMNI_CLOUD_SPEED 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"云亮度","en_us":"Cloud brightness"},"slider":true}
#define OMNI_CLOUD_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5]
// @option {"label":{"zh_cn":"云色冷暖","en_us":"Cloud warmth"},"slider":true}
#define OMNI_CLOUD_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"云边缘透光","en_us":"Cloud edge glow"},"description":{"zh_cn":"对着太阳看云时边缘发亮、背对时偏暗。","en_us":"Cloud edges brighten toward the sun and dim away from it."},"slider":true}
#define OMNI_CLOUD_SILVER 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"云影开关","en_us":"Cloud shadow"}}
#define OMNI_CLOUD_SHADOW 1 // [0 1]
// @option {"label":{"zh_cn":"云影浓淡","en_us":"Cloud shadow strength"},"slider":true}
#define OMNI_CLOUD_SHADOW_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"云精细度","en_us":"Cloud detail"},"description":{"zh_cn":"云沿视线的采样次数；越高越厚实也越耗性能。","en_us":"Samples along the view; higher is denser but costlier."}}
#define OMNI_CLOUD_STEPS 16 // [8 16 32]
// 天空颜色与云照明共享天体输入；加载器输入显式引入，不依赖间接包含。
#include "/common/uniforms.glsl"
#include "/effects/sky.glsl"
// 成熟无纹理梯度噪声直接构建云密度，不为库增加只转手的包装。
#include "/libraries/ashima/noise3D.glsl"
// --- 云量：把菜单里的百分比收敛到零到一 ---
float omniCloudCoverage() {
    return clamp(OMNI_CLOUD_COVERAGE,0.0,1.0); // 越界配置收敛到有效区间。
}
// --- 云密度：低频轮廓叠高频碎边，再按云量取阈值 ---
// 单一频率的噪声像一块均匀的棉花，叠上低频形状和高频碎边才既有轮廓又有毛边。
float omniCloudDensity(vec3 p) {
    float coverage = omniCloudCoverage(); // 收敛到零到一的云量。
    if (coverage<=0.0) return 0.0; // 云量为零时明确没有云，也省下噪声采样。
    p.x += frameTimeCounter*OMNI_CLOUD_SPEED*2.0; // 风沿水平方向推移噪声，云看起来在飘。
    float shape = snoise(p*vec3(0.004,0.018,0.004)*OMNI_CLOUD_SCALE)*0.7; // 低频决定云块大轮廓，竖直方向压缩让云更扁。
    float detail = snoise(p*0.013*OMNI_CLOUD_SCALE)*0.3; // 高频给云块加碎边，避免轮廓太光滑。
    float n = 0.5+0.5*(shape+detail); // 噪声从负一到一映射到零到一。
    return smoothstep(0.8-coverage*0.5,0.95-coverage*0.5,n); // 云量越高阈值越低，云越满。
}
// --- 云影：从地表沿光线穿过整层云，按密度扣掉直射光 ---
// 方向取当前阴影天体（太阳或月亮）的世界方向，所以夜晚的月光同样会被云挡；
// 而云自身的亮度与银边用太阳方向判断昼夜（见 omniCloudSilver 与 omniCloudColor）。
// 关键：云影与可见云用同一份密度和同一套边缘渐薄、同一消光系数，只是采样方向不同，
// 所以天上云越厚、地上影越深，薄云与高云的地影也会跟着变淡。
float omniCloudShadow(vec3 world) {
#if OMNI_CLOUD_SHADOW == 0 || defined OMNI_NETHER || defined OMNI_END
    return 1.0; // 关闭云影，或该维度没有自定义云时，直射光完全不受影响。
#else
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse)*shadowLightPosition); // 阴影天体在世界空间里的方向。
    if (sun.y<=0.03) return 1.0; // 天体贴近地平线时方向太斜，忽略云影避免出现超长阴影。
    float surfaceY = world.y+cameraPosition.y; // 地表的绝对高度。
    float lower = (OMNI_CLOUD_HEIGHT-surfaceY)/sun.y; // 光线进入云层下界的距离。
    float upper = (OMNI_CLOUD_HEIGHT+OMNI_CLOUD_THICKNESS-surfaceY)/sun.y; // 光线离开云层上界的距离。
    if (upper<=0.0) return 1.0; // 地表已在云层之上或光线不向上，没有云可挡。
    float begin = max(lower,0.0); // 地表已经进入云层时从零开始。
    float stepMeters = (upper-begin)/float(OMNI_CLOUD_STEPS); // 与可见云同一精细度，改云精细度时云影一并变化。
    float optical = 0.0; // 按米累计的光学厚度。
    for (int i=0;i<OMNI_CLOUD_STEPS;i++) {
        vec3 p = world+cameraPosition+sun*(begin+(float(i)+0.5)*stepMeters); // 只在实际云层高度区间内取样。
        float height = (p.y-OMNI_CLOUD_HEIGHT)/OMNI_CLOUD_THICKNESS; // 相对云层中面的高度，零到一。
        float density = omniCloudDensity(p)*smoothstep(0.0,0.2,height)*(1.0-smoothstep(0.7,1.0,height)); // 与可见云同一套上下边缘渐薄。
        optical += density*stepMeters; // 用米累积，和可见云的消光口径一致。
    }
    float fade = smoothstep(0.03,0.15,sun.y); // 天体越低云影越淡。
    return mix(1.0,exp(-optical*0.07*OMNI_CLOUD_SHADOW_STRENGTH),fade); // 0.07 与可见云同一消光系数；浓淡取零等于没有云影。
#endif
}
// --- 云的昼夜颜色：受昼夜、天气、亮度与冷暖共同控制 ---
vec3 omniCloudColor(vec3 nightColor, vec3 dayColor) {
    float up = omniNormalize(mat3(gbufferModelViewInverse)*sunPosition).y; // 天体方向的世界高度。
    float lit = smoothstep(-0.15,0.1,up); // 天体越接近天顶，云越亮。
    vec3 color = mix(nightColor,dayColor,lit)*(1.0-rainStrength*0.6); // 雨天把云整体压暗。
    color *= OMNI_CLOUD_BRIGHTNESS; // 整体亮度，取一保持原有明暗。
    return color*exp(vec3(0.2,0.0,-0.2)*OMNI_CLOUD_TINT); // 冷暖偏移，取零保持中性。
}
// --- 云的前向散射（银边）：逆着太阳看云更亮，顺着看偏暗 ---
// 为什么只改亮度不改颜色：前向散射主要改变受光量，颜色已由昼夜与冷暖选项控制。
float omniCloudSilver(vec3 direction) {
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse)*sunPosition); // 太阳在世界空间的方向。
    float facing = max(dot(omniNormalize(direction),sun),0.0); // 视线与太阳方向夹角余弦。
    return 1.0+OMNI_CLOUD_SILVER*(pow(facing,4.0)*1.2-0.4); // 正向增亮、背向压暗；取零恒为一。
}
// --- 云入口：沿视线在云层高度区间内做体积透射积分 ---
vec3 omniCloud(vec3 color, vec3 direction, float sceneDistance) {
#if defined OMNI_NETHER || defined OMNI_END
    return color; // 下界与末地没有自定义云，交给各自的天空。
#else
    vec3 d = omniNormalize(direction); // 米制步进方向。
    if (abs(d.y)<0.005) return color; // 视线几乎水平，不与云层相交。
    float lowerCross = (OMNI_CLOUD_HEIGHT-cameraPosition.y)/d.y; // 视线穿过云层下界的距离。
    float upperCross = (OMNI_CLOUD_HEIGHT+OMNI_CLOUD_THICKNESS-cameraPosition.y)/d.y; // 视线穿过云层上界的距离。
    float begin = max(min(lowerCross,upperCross),0.0); // 相机在云层内部时从零开始步进。
    float end = min(max(lowerCross,upperCross),min(sceneDistance,18000.0)); // 步进在地形前或云层上界停下。
    if (end<=begin) return color; // 云在相机身后或被地形挡住，不画。
    float stride = (end-begin)/float(OMNI_CLOUD_STEPS); // 步数可调，步长按区间均分。
    float opacity = 0.0; // 累计体积透射损失，零表示完全透明。
    for (int i=0;i<OMNI_CLOUD_STEPS;i++) {
        vec3 p = cameraPosition+d*(begin+(float(i)+0.5)*stride); // 采样点落在每一步的中心。
        float height = (p.y-OMNI_CLOUD_HEIGHT)/OMNI_CLOUD_THICKNESS; // 相对云层中面的高度，零到一。
        float density = omniCloudDensity(p)*smoothstep(0.0,0.2,height)*(1.0-smoothstep(0.7,1.0,height)); // 上下边缘渐薄，避免云层像一块板。
        opacity += (1.0-opacity)*(1.0-exp(-density*stride*0.07)); // 前向透射积分，后面的采样只影响剩余可见部分。
    }
    vec3 cloudColor = omniCloudColor(vec3(0.035,0.047,0.07),vec3(0.85,0.86,0.88))*omniCloudSilver(d); // 体积云偏灰，并按银边受光调整明暗。
    return mix(color,cloudColor,clamp(opacity,0.0,1.0)); // 用不透明度把云混到天空上。
#endif
}
#endif
