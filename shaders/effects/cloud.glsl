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
  两套做法可切换：体积云沿视线在云层高度区间里步进，厚实有层次；平面云只算视线与云平面的
  交点，更省也更像一张连续的天际线。两者共用同一份夜色/日色与银边，切换时色调不会突变。
  形状、颜色、云影都从同一层云出发，所以眼见的云和地上的云影对得上；
  平面做法下云影也沿同一阴影方向投到同一张云平面上，保持可见云与云影一致。
  采样步数做成「云精细度」选项，玩家在更细致和更省性能之间自己取舍。
  下界和末地没有真实大气，本文件直接返回原色，交给各自的天空处理。
*/
#ifndef OMNI_CLOUD
#define OMNI_CLOUD
// @effect {"label":{"zh_cn":"云","en_us":"Clouds"}}
// @option {"label":{"zh_cn":"云的做法","en_us":"Cloud style"},"description":{"zh_cn":"体积云沿视线在云层里一步步取样，厚实有层次；平面云把云画在一层水平面上，更省也更平。","en_us":"Volumetric marches through the layer for depth; planar draws the clouds on one horizontal sheet, cheaper and flatter."},"values":{"0":{"zh_cn":"体积","en_us":"Volumetric"},"1":{"zh_cn":"平面","en_us":"Planar"}}}
#define OMNI_CLOUD_MODE 0 // [0 1]
// @option {"label":{"zh_cn":"云量","en_us":"Cloud amount"},"description":{"zh_cn":"天上有多少云；调高云更满更连片，取零就没有云。","en_us":"How much cloud covers the sky; higher is fuller, zero means no clouds."},"slider":true}
#define OMNI_CLOUD_COVERAGE 0.5 // [0.0 0.25 0.5 0.75 1.0]
// @option {"label": {"zh_cn": "云高度", "en_us": "Cloud height"}, "description": {"zh_cn": "云挂得多高。", "en_us": "How high the clouds sit."}}
#define OMNI_CLOUD_HEIGHT 192.0 // [128.0 192.0 256.0 320.0]
// @option {"label":{"zh_cn":"云厚度","en_us":"Cloud thickness"},"description":{"zh_cn":"云层有多厚；也决定云影要穿过多少云。","en_us":"How thick the cloud layer is; also the depth the cloud shadow marches."}}
#define OMNI_CLOUD_THICKNESS 32.0 // [16.0 32.0 64.0 128.0]
// @option {"label":{"zh_cn":"云密度","en_us":"Cloud density"},"description":{"zh_cn":"晴天时云本身多不透光；调高云更厚实、更挡光。","en_us":"How opaque the clouds are in clear weather; higher is denser and blocks more light."},"slider":true}
#define OMNI_CLOUD_DENSITY 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"云块大小","en_us":"Cloud size"},"description":{"zh_cn":"大于一云块更小更碎，小于一云块更大更整。","en_us":"Above one makes smaller broken clouds, below one makes larger solid clouds."},"slider":true}
#define OMNI_CLOUD_SCALE 1.0 // [0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"云噪声尺度","en_us":"Cloud noise scale"},"description":{"zh_cn":"云块边缘碎边噪声的尺度；调高碎边更细更碎。","en_us":"Scale of the fine noise on cloud edges; higher makes the edges finer and more broken."},"slider":true}
#define OMNI_CLOUD_NOISE_SCALE 1.0 // [0.5 1.0 1.5 2.0]
// @option {"label": {"zh_cn": "云速", "en_us": "Cloud speed"}, "slider": true, "description": {"zh_cn": "云飘得快慢。", "en_us": "How fast the clouds drift."}}
#define OMNI_CLOUD_SPEED 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label": {"zh_cn": "云亮度", "en_us": "Cloud brightness"}, "slider": true, "description": {"zh_cn": "云整体亮暗。", "en_us": "Overall cloud brightness."}}
#define OMNI_CLOUD_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5]
// @option {"label": {"zh_cn": "云色冷暖", "en_us": "Cloud warmth"}, "slider": true, "description": {"zh_cn": "云偏暖还是偏冷。", "en_us": "Warms or cools the clouds."}}
#define OMNI_CLOUD_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"云边缘透光","en_us":"Cloud edge glow"},"description":{"zh_cn":"对着太阳看云时边缘发亮、背对时偏暗。","en_us":"Cloud edges brighten toward the sun and dim away from it."},"slider":true}
#define OMNI_CLOUD_SILVER 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"云底亮度","en_us":"Cloud base light"},"description":{"zh_cn":"云背光面（夜里、阴雨、背对太阳）留下的底光；取零时背光云会变很暗。","en_us":"Base light kept on shaded cloud sides (night, overcast, away from the sun); zero lets them go very dark."},"slider":true}
#define OMNI_CLOUD_BOTTOM 0.15 // [0.0 0.05 0.1 0.15 0.25 0.4]
// @option {"label":{"zh_cn":"云外散射","en_us":"Cloud outscatter"},"description":{"zh_cn":"阳光透过云向四周散开的集中程度；调高光更集中在太阳方向。","en_us":"How tightly light spreads out of the clouds toward the sun; higher concentrates it around the sun."},"slider":true}
#define OMNI_CLOUD_OUTSCATTER 4.0 // [1.0 2.0 3.0 4.0 6.0 8.0]
// @option {"label":{"zh_cn":"云受光","en_us":"Cloud direct light"},"description":{"zh_cn":"晴天阳光照在云顶上的强度；调低云更灰更沉。","en_us":"How strongly the sun lights the cloud tops in clear weather; lower makes them greyer."},"slider":true}
#define OMNI_CLOUD_SUNLIGHT 1.0 // [0.0 0.5 0.75 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"云天光","en_us":"Cloud skylight"},"description":{"zh_cn":"晴天云背光面与夜里剩下的底光。","en_us":"The sky light left on shaded cloud sides and at night in clear weather."},"slider":true}
#define OMNI_CLOUD_SKYLIGHT 1.0 // [0.0 0.5 0.75 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"雨天云量","en_us":"Rain cloud amount"},"description":{"zh_cn":"下雨时天上云量取代晴天云量，雨越大越靠近这个值。","en_us":"Cloud amount used while it rains, replacing the clear-weather value as rain builds."},"slider":true}
#define OMNI_CLOUD_RAIN_COVERAGE 0.95 // [0.0 0.25 0.5 0.75 0.95 1.0]
// @option {"label":{"zh_cn":"雨天云厚度","en_us":"Rain cloud thickness"},"description":{"zh_cn":"下雨时云层有多厚，取代晴天云厚度。","en_us":"Cloud layer thickness while it rains, replacing the clear-weather value."}}
#define OMNI_CLOUD_RAIN_THICKNESS 64.0 // [16.0 32.0 64.0 128.0]
// @option {"label":{"zh_cn":"雨天云密度","en_us":"Rain cloud density"},"description":{"zh_cn":"下雨时云多不透光，取代晴天云密度。","en_us":"Cloud opacity while it rains, replacing the clear-weather value."},"slider":true}
#define OMNI_CLOUD_RAIN_DENSITY 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"雨天云块大小","en_us":"Rain cloud size"},"description":{"zh_cn":"下雨时云块大小，取代晴天云块大小。","en_us":"Cloud block size while it rains, replacing the clear-weather value."},"slider":true}
#define OMNI_CLOUD_RAIN_SCALE 1.0 // [0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"雨天云受光","en_us":"Rain cloud direct light"},"description":{"zh_cn":"下雨时云受的直射光；调低雨天云更阴。","en_us":"Direct light on clouds while it rains; lower makes rainy clouds darker."},"slider":true}
#define OMNI_CLOUD_RAIN_SUNLIGHT 0.4 // [0.0 0.1 0.25 0.4 0.6 0.8 1.0]
// @option {"label":{"zh_cn":"雨天云天光","en_us":"Rain cloud skylight"},"description":{"zh_cn":"下雨时云受的天光，决定阴云的底色。","en_us":"Sky light on clouds while it rains, setting the base tone of overcast clouds."},"slider":true}
#define OMNI_CLOUD_RAIN_SKYLIGHT 0.8 // [0.0 0.25 0.5 0.8 1.0 1.5]
// @option {"label":{"zh_cn":"云淡出距离","en_us":"Cloud fade distance"},"description":{"zh_cn":"超过这个距离的云逐渐融进天空，避免远处出现硬边。","en_us":"Clouds fade into the sky beyond this distance, avoiding hard edges far away."}}
#define OMNI_CLOUD_FADE 18000.0 // [4000.0 8000.0 12000.0 18000.0 24000.0]
// @option {"label": {"zh_cn": "云影开关", "en_us": "Cloud shadow"}, "description": {"zh_cn": "云要不要在地上投下阴影。", "en_us": "Whether clouds cast shadows on the ground."}, "values": {"0": {"zh_cn": "关", "en_us": "Off"}, "1": {"zh_cn": "开", "en_us": "On"}}}
#define OMNI_CLOUD_SHADOW 1 // [0 1]
// @option {"label": {"zh_cn": "云影浓淡", "en_us": "Cloud shadow strength"}, "slider": true, "description": {"zh_cn": "云影有多明显。", "en_us": "How dark the cloud shadows are."}}
#define OMNI_CLOUD_SHADOW_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label": {"zh_cn": "云影影响天光", "en_us": "Cloud shadow on skylight"}, "slider": true, "description": {"zh_cn": "云挡住太阳时，除了直射光变暗，环境光也跟着暗多少；取零只压直射光。", "en_us": "How much the ambient light dims under cloud shadow in addition to the direct light; zero dims only the direct light."}}
#define OMNI_CLOUD_SHADOW_AMBIENT 0.5 // [0.0 0.25 0.5 0.75 1.0]
// @option {"label": {"zh_cn": "云精细度", "en_us": "Cloud detail"}, "description": {"zh_cn": "云沿视线的采样次数；越高越厚实也越耗性能。", "en_us": "Samples along the view; higher is denser but costlier."}, "values": {"8": {"zh_cn": "低", "en_us": "Low"}, "16": {"zh_cn": "中", "en_us": "Medium"}, "32": {"zh_cn": "高", "en_us": "High"}}}
#define OMNI_CLOUD_STEPS 16 // [8 16 32]
// 天空颜色与云照明共享天体输入；加载器输入显式引入，不依赖间接包含。
#include "/common/uniforms.glsl"
#include "/effects/sky.glsl"
// 成熟无纹理梯度噪声直接构建云密度，不为库增加只转手的包装。
#include "/libraries/ashima/noise3D.glsl"
// --- 天气权重：零为晴、一为雨，驱动云在两套参数之间切换 ---
// 为什么用湿润度而不是降雨强度：湿润度在雨停后仍缓慢回落，云散得比雨停晚，过渡更自然。
float omniCloudWeather() {
    return clamp(wetness,0.0,1.0); // 越界配置收敛到有效区间。
}
// --- 云量：晴天与雨天两档，按天气权重取值 ---
float omniCloudCoverage() {
    float coverage = mix(OMNI_CLOUD_COVERAGE,OMNI_CLOUD_RAIN_COVERAGE,omniCloudWeather()); // 雨越大越靠近雨天云量。
    return clamp(coverage,0.0,1.0); // 越界配置收敛到有效区间。
}
// --- 云层厚度：晴天与雨天两档 ---
float omniCloudThickness() {
    float thickness = mix(OMNI_CLOUD_THICKNESS,OMNI_CLOUD_RAIN_THICKNESS,omniCloudWeather()); // 雨天云更厚。
    return max(thickness,1.0); // 至少一米的厚度，避免零厚度导致步长为零。
}
// --- 云密度倍率：晴天与雨天两档 ---
float omniCloudDensityMul() {
    return max(mix(OMNI_CLOUD_DENSITY,OMNI_CLOUD_RAIN_DENSITY,omniCloudWeather()),0.0); // 雨天云更不透光。
}
// --- 云块大小：晴天与雨天两档 ---
float omniCloudScale() {
    return max(mix(OMNI_CLOUD_SCALE,OMNI_CLOUD_RAIN_SCALE,omniCloudWeather()),0.01); // 至少一个极小值，避免噪声频率退化为零。
}
// --- 云受光：晴天与雨天两档 ---
float omniCloudSunlight() {
    return max(mix(OMNI_CLOUD_SUNLIGHT,OMNI_CLOUD_RAIN_SUNLIGHT,omniCloudWeather()),0.0); // 雨天直射光被云层挡掉更多。
}
// --- 云天光：晴天与雨天两档 ---
float omniCloudSkylight() {
    return max(mix(OMNI_CLOUD_SKYLIGHT,OMNI_CLOUD_RAIN_SKYLIGHT,omniCloudWeather()),0.0); // 雨天阴云主要靠天光染亮。
}
// --- 云密度：低频轮廓叠高频碎边，再按云量取阈值 ---
// 单一频率的噪声像一块均匀的棉花，叠上低频形状和高频碎边才既有轮廓又有毛边。
float omniCloudDensity(vec3 p) {
    float coverage = omniCloudCoverage(); // 收敛到零到一的云量。
    if (coverage<=0.0) return 0.0; // 云量为零时明确没有云，也省下噪声采样。
    p.x += frameTimeCounter*OMNI_CLOUD_SPEED*2.0; // 风沿水平方向推移噪声，云看起来在飘。
    float shape = snoise(p*vec3(0.004,0.018,0.004)*omniCloudScale())*0.7; // 低频决定云块大轮廓，竖直方向压缩让云更扁。
    float detail = snoise(p*0.013*omniCloudScale()*OMNI_CLOUD_NOISE_SCALE)*0.3; // 高频给云块加碎边，碎边尺度由噪声尺度单独控制。
    float n = 0.5+0.5*(shape+detail); // 噪声从负一到一映射到零到一。
    return smoothstep(0.8-coverage*0.5,0.95-coverage*0.5,n); // 云量越高阈值越低，云越满。
}
// --- 平面云密度：把云摊在一层水平面上，用几层噪声叠出连续云块 ---
// 为什么可直接投到平面：平面云挂在固定高度，从地面往上看就是一层贴片，不需要沿视线步进，
// 所以代价与云厚度无关；代价换来的是缺少立体感，因此只作为可选做法。
float omniPlanarDensity(vec2 xz) {
    float coverage = omniCloudCoverage(); // 与体积云共用同一个云量选项。
    if (coverage<=0.0) return 0.0; // 云量为零时明确没有云，也省下噪声采样。
    vec2 wind = vec2(frameTimeCounter*OMNI_CLOUD_SPEED*0.01,frameTimeCounter*OMNI_CLOUD_SPEED*0.004)*100.0; // 水平风向，缓慢平移噪声；一百倍让云速手感与体积云接近。
    vec2 uv = xz*0.0016*omniCloudScale()+wind; // 空间频率决定云块大小，与体积云同量级。
    float n = 0.0; float amplitude = 0.5; float frequency = 1.0; // 起始层振幅与频率。
    for (int i=0;i<4;i++) {
        n += snoise(vec3(uv*frequency,float(i)*3.7))*amplitude; // 每层换一个高度当种子，避免层与层重复。
        frequency *= 2.1; amplitude *= 0.5; // 频率变高、振幅减半，形成由大到细的层次。
    }
    float threshold = 0.75-coverage*0.45; // 云量越高阈值越低，云越满。
    return smoothstep(threshold,threshold+0.25,0.5+0.5*n); // 把噪声收敛成零到一的密度。
}
// --- 云影：从地表沿光线穿过整层云，按密度扣掉直射光 ---
// 方向取当前阴影天体（太阳或月亮）的世界方向，所以夜晚的月光同样会被云挡；
// 而云自身的亮度与银边用太阳方向判断昼夜（见 omniCloudSilver 与 omniCloudColor）。
// 关键：云影与可见云用同一份密度和同一套边缘渐薄、同一消光系数，只是采样方向不同，
// 所以天上云越厚、地上影越深，薄云与高云的地影也会跟着变淡；
// 平面做法下改成把地表沿光线投到同一张云平面上取密度，可见云与云影仍然对得上。
float omniCloudShadow(vec3 world) {
#if OMNI_CLOUD_SHADOW == 0 || defined OMNI_NETHER || defined OMNI_END
    return 1.0; // 关闭云影，或该维度没有自定义云时，直射光完全不受影响。
#else
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse)*shadowLightPosition); // 阴影天体在世界空间里的方向。
    if (sun.y<=0.03) return 1.0; // 天体贴近地平线时方向太斜，忽略云影避免出现超长阴影。
    float surfaceY = world.y+cameraPosition.y; // 地表的绝对高度。
#if OMNI_CLOUD_MODE == 1
    if (surfaceY>OMNI_CLOUD_HEIGHT) return 1.0; // 平面云：地表已在云层之上，没有云可挡。
    vec2 hit = (world+cameraPosition).xz+sun.xz*((OMNI_CLOUD_HEIGHT-surfaceY)/sun.y); // 从地表沿光线投到云平面的落点，与可见平面云取同一张噪声。
    float optical = omniPlanarDensity(hit)*omniCloudThickness(); // 平面云的等效光程按整层厚度折算。
    float fade = smoothstep(0.03,0.15,sun.y); // 天体越低云影越淡。
    return mix(1.0,exp(-optical*0.07*omniCloudDensityMul()*OMNI_CLOUD_SHADOW_STRENGTH),fade); // 0.07 与可见云同一消光系数；浓淡取零等于没有云影。
#else
    float lower = (OMNI_CLOUD_HEIGHT-surfaceY)/sun.y; // 光线进入云层下界的距离。
    float upper = (OMNI_CLOUD_HEIGHT+omniCloudThickness()-surfaceY)/sun.y; // 光线离开云层上界的距离。
    if (upper<=0.0) return 1.0; // 地表已在云层之上或光线不向上，没有云可挡。
    float begin = max(lower,0.0); // 地表已经进入云层时从零开始。
    float stepMeters = (upper-begin)/float(OMNI_CLOUD_STEPS); // 与可见云同一精细度，改云精细度时云影一并变化。
    float optical = 0.0; // 按米累计的光学厚度。
    for (int i=0;i<OMNI_CLOUD_STEPS;i++) {
        vec3 p = world+cameraPosition+sun*(begin+(float(i)+0.5)*stepMeters); // 只在实际云层高度区间内取样。
        float height = (p.y-OMNI_CLOUD_HEIGHT)/omniCloudThickness(); // 相对云层中面的高度，零到一。
        float density = omniCloudDensity(p)*smoothstep(0.0,0.2,height)*(1.0-smoothstep(0.7,1.0,height)); // 与可见云同一套上下边缘渐薄。
        optical += density*stepMeters; // 用米累积，和可见云的消光口径一致。
    }
    float fade = smoothstep(0.03,0.15,sun.y); // 天体越低云影越淡。
    return mix(1.0,exp(-optical*0.07*omniCloudDensityMul()*OMNI_CLOUD_SHADOW_STRENGTH),fade); // 0.07 与可见云同一消光系数；浓淡取零等于没有云影。
#endif
#endif
}
// --- 云的昼夜颜色：受昼夜、天气、亮度与冷暖共同控制 ---
// 参考把云分成直射与天光两部分：太阳照亮云顶，天光托住背光面与夜里的底色。
// 晴天下两项都取一，结果与旧的昼夜插值完全一致，所以默认画面不变；
// 雨天两档分别压暗直射、保留天光，阴云自然变灰，不必再额外乘一个降雨系数。
vec3 omniCloudColor(vec3 nightColor, vec3 dayColor) {
    float up = omniNormalize(mat3(gbufferModelViewInverse)*sunPosition).y; // 天体方向的世界高度。
    float lit = smoothstep(-0.15,0.1,up); // 天体越接近天顶，云越亮。
    vec3 direct = dayColor*lit*omniCloudSunlight(); // 直射分量：太阳照亮的云顶。
    vec3 ambient = nightColor*(1.0-lit)*omniCloudSkylight(); // 天光分量：背光面与夜晚的底色。
    vec3 color = max(direct+ambient,dayColor*OMNI_CLOUD_BOTTOM*(1.0-lit*0.5)); // 云底亮度：受光越弱底光越明显，背光云底不会全黑。
    color *= OMNI_CLOUD_BRIGHTNESS; // 整体亮度，取一保持原有明暗。
    return color*exp(vec3(0.2,0.0,-0.2)*OMNI_CLOUD_TINT); // 冷暖偏移，取零保持中性。
}
// --- 云的前向散射（银边）：逆着太阳看云更亮，顺着看偏暗 ---
// 为什么只改亮度不改颜色：前向散射主要改变受光量，颜色已由昼夜与冷暖选项控制。
float omniCloudSilver(vec3 direction) {
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse)*sunPosition); // 太阳在世界空间的方向。
    float facing = max(dot(omniNormalize(direction),sun),0.0); // 视线与太阳方向夹角余弦。
    return 1.0+OMNI_CLOUD_SILVER*(pow(facing,OMNI_CLOUD_OUTSCATTER)*1.2-0.4); // 正向增亮、背向压暗；指数由外散射控制，取银边零时恒为一。
}
// --- 平面云入口：视线与云平面相交后只取一次密度 ---
// 为什么不做体积步进：平面云本身就是一层贴片，取一次交点密度就够，代价与云厚度无关。
vec3 omniPlanarCloud(vec3 color, vec3 direction) {
    vec3 d = omniNormalize(direction); // 归一化视线方向。
    if (d.y<0.02) return color; // 视线几乎水平或朝下，与云平面没有可见交点。
    float travel = (OMNI_CLOUD_HEIGHT-cameraPosition.y)/d.y; // 视线到达云平面的距离。
    if (travel<=0.0) return color; // 相机在云层之上且朝上看不到这层平面。
    vec3 hit = cameraPosition+d*travel; // 交点世界坐标，用来取平面噪声。
    float density = omniPlanarDensity(hit.xz); // 交点处的云密度。
    if (density<=0.0) return color; // 交点落在云缝里，直接透出天空。
    float horizon = smoothstep(0.02,0.15,d.y); // 越靠地平线云压得越扁，淡出避免拉花。
    float far = max(OMNI_CLOUD_FADE,1000.0); // 云的可见最远距离，至少一千米避免配置错误时整片消失。
    float fade = 1.0-smoothstep(far*0.5,far,travel); // 越接近淡出距离越透明，远处云融进天空。
    vec3 cloudColor = omniCloudColor(vec3(0.035,0.047,0.07),vec3(0.85,0.86,0.88))*omniCloudSilver(d); // 与体积云共用同一套昼夜颜色与银边。
    return mix(color,cloudColor,clamp(density*horizon*fade,0.0,1.0)); // 用不透明度把云混到天空上。
}
// --- 云入口：按做法选择体积步进或平面取点 ---
vec3 omniCloud(vec3 color, vec3 direction, float sceneDistance) {
#if defined OMNI_NETHER || defined OMNI_END
    return color; // 下界与末地没有自定义云，交给各自的天空。
#elif OMNI_CLOUD_MODE == 1
    return omniPlanarCloud(color,direction); // 平面云只求一次交点，不做体积步进。
#else
    vec3 d = omniNormalize(direction); // 米制步进方向。
    if (abs(d.y)<0.005) return color; // 视线几乎水平，不与云层相交。
    float lowerCross = (OMNI_CLOUD_HEIGHT-cameraPosition.y)/d.y; // 视线穿过云层下界的距离。
    float upperCross = (OMNI_CLOUD_HEIGHT+omniCloudThickness()-cameraPosition.y)/d.y; // 视线穿过云层上界的距离。
    float begin = max(min(lowerCross,upperCross),0.0); // 相机在云层内部时从零开始步进。
    float far = max(OMNI_CLOUD_FADE,1000.0); // 云的可见最远距离，至少一千米避免配置错误时整片消失。
    float end = min(max(lowerCross,upperCross),min(sceneDistance,far)); // 步进在地形前、云层上界或云淡出距离停下。
    if (end<=begin) return color; // 云在相机身后或被地形挡住，不画。
    float stride = (end-begin)/float(OMNI_CLOUD_STEPS); // 步数可调，步长按区间均分。
    float opacity = 0.0; // 累计体积透射损失，零表示完全透明。
    for (int i=0;i<OMNI_CLOUD_STEPS;i++) {
        vec3 p = cameraPosition+d*(begin+(float(i)+0.5)*stride); // 采样点落在每一步的中心。
        float height = (p.y-OMNI_CLOUD_HEIGHT)/omniCloudThickness(); // 相对云层中面的高度，零到一。
        float density = omniCloudDensity(p)*smoothstep(0.0,0.2,height)*(1.0-smoothstep(0.7,1.0,height)); // 上下边缘渐薄，避免云层像一块板。
        opacity += (1.0-opacity)*(1.0-exp(-density*stride*0.07*omniCloudDensityMul())); // 前向透射积分，后面的采样只影响剩余可见部分；密度倍率按晴雨切换。
    }
    opacity *= 1.0-smoothstep(far*0.5,far,end); // 越接近淡出距离越透明，远处云融进天空不留硬边。
    vec3 cloudColor = omniCloudColor(vec3(0.035,0.047,0.07),vec3(0.85,0.86,0.88))*omniCloudSilver(d); // 体积云偏灰，并按银边受光调整明暗。
    return mix(color,cloudColor,clamp(opacity,0.0,1.0)); // 用不透明度把云混到天空上。
#endif
}
#endif
