/*
云：给天空画云，并让地表的直射光按云层密度变暗。三种画法共享同一套云密度与云色。

在什么位置被调用：
  rendering/composite.glsl 在几何绘制之前调用，用来让云遮住地形之后的天空。
  rendering/lighting.glsl 在天空背景里先算天空色，再叠云与氛围。
  effects/sunlight.glsl 取用地表的云影来衰减直射光。

可直接复制的最小示例：
  `vec3 天空 = omniCloud(omniSky(方向), 方向, 32000.0);`
  `float 阳光 = omniCloudShadow(世界坐标);`

关键设计原因与取舍：
  天空看到的云和地表云影必须来自同一种密度，否则阴影位置和眼见的云对不上，
  所以密度只写一份（omniCloudDensity），三种画法各自只负责从哪里取点。
  体积云固定 16 步而不是自适应步长：步数写死，编译结果可预测，弱显卡也不会突然掉帧。
  平面云只做射线与高度平面求交，不步进体积，省算力，代价是看不出云的厚度和侧面。
  云影只用 4 次稀疏采样估计光学厚度，够表达云下变暗，不追求和体积云逐像素一致。
  下界和末地没有真实大气，本文件一律直接返回原色，交给各自的天空处理。
*/
#ifndef OMNI_CLOUD
#define OMNI_CLOUD
// @effect {"label":{"zh_cn":"云","en_us":"Clouds"}}
// @option {"label":{"zh_cn":"云算法","en_us":"Cloud mode"},"description":{"zh_cn":"零关闭，一单层，二体积，三平面地平线云层；平面模式用分形噪声铺满水平面。","en_us":"Off, single layer, volume, or a planar horizon layer built from fractal noise."}}
#define OMNI_CLOUD_MODE 1 // [0 1 2 3]
// @option {"label":{"zh_cn":"云覆盖率","en_us":"Cloud coverage"},"slider":true}
#define OMNI_CLOUD_COVERAGE 0.5 // [0.25 0.5 0.75 1.0]
// @option {"label":{"zh_cn":"云高度","en_us":"Cloud altitude"}}
#define OMNI_CLOUD_HEIGHT 192.0 // [128.0 192.0 256.0 320.0]
// @option {"label":{"zh_cn":"云速度","en_us":"Cloud speed"},"slider":true}
#define OMNI_CLOUD_SPEED 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"云颜色冷暖","en_us":"Cloud color temperature"},"slider":true}
#define OMNI_CLOUD_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"云影","en_us":"Cloud shadow"},"description":{"zh_cn":"地表直射光沿光线方向按云密度衰减。","en_us":"Attenuates direct sunlight by cloud density along the light direction."}}
#define OMNI_CLOUD_SHADOW 1 // [0 1]
// 天空颜色与云照明共享天体输入。
#include "/effects/sky.glsl"
// 成熟无纹理梯度噪声直接构建体积云密度，不为库增加只转手的包装。
#include "/libraries/ashima/noise3D.glsl"
// --- 云覆盖率：把菜单里的百分比收敛到零到一 ---
// 边界只在这里检查一次，三种云都从这里取覆盖率，越界配置不会把后面的密度算成负数。
float omniCloudCoverage() {
    return clamp(OMNI_CLOUD_COVERAGE, 0.0, 1.0); // 配置越界时收敛到有效区间。
}
// --- 体积云密度：两个频率相加后按覆盖率取阈值 ---
// 单一频率的噪声看起来像一块均匀的棉花，叠上低频形状和高频碎边才既有轮廓又有毛边。
float omniCloudDensity(vec3 p) {
    float coverage = omniCloudCoverage(); // 收敛到零到一的云覆盖率。
    p.x += frameTimeCounter * OMNI_CLOUD_SPEED * 2.0; // 风沿水平方向推移噪声，云看起来在飘。
    float shape = snoise(p * vec3(0.004,0.018,0.004)) * 0.7; // 低频决定云块大轮廓，竖直方向压缩让云更扁。
    float detail = snoise(p * 0.013) * 0.3; // 高频给云块加碎边，避免轮廓太光滑。
    float n = 0.5 + 0.5 * (shape + detail); // 噪声原本在负一到一之间，映射到零到一。
    return smoothstep(0.8 - coverage * 0.5, 0.95 - coverage * 0.5, n); // 覆盖率越高阈值越低，云越满。
}
// --- 云影遮挡：从地表沿光线走到云层，按密度扣掉直射光 ---
// 方向取当前天体（太阳或月亮）的世界方向，所以夜晚的月光同样会被云挡。
float omniCloudShadow(vec3 world) {
#if OMNI_CLOUD_SHADOW == 0 || defined OMNI_NETHER || defined OMNI_END
    return 1.0; // 关闭云影，或该维度没有自定义云时，直射光完全不受影响。
#else
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse)*shadowLightPosition); // 天体在世界空间里的方向。
    if (sun.y<=0.03) return 1.0; // 天体贴近地平线时方向太斜，忽略云影避免出现超长阴影。
    float surfaceY = world.y+cameraPosition.y; // 地表的绝对高度，用来算它离云层还有多远。
    float travel = (OMNI_CLOUD_HEIGHT-surfaceY)/sun.y; // 沿光线从地表走到云层下界的距离。
    if (travel<=0.0) return 1.0; // 地表已在云层之上或光线不向上，没有云可挡。
    float optical = 0.0; // 累计的光学厚度，越大表示路上云越多。
    for (int i=0;i<4;i++) {
        vec3 p = world+cameraPosition+sun*travel*((float(i)+0.5)/4.0); // 在云层段内均匀取四个点。
        optical += omniCloudDensity(p); // 用少量采样估计整段密度，够表达云下变暗。
    }
    float fade = smoothstep(0.03,0.15,sun.y); // 天体越低云影越淡，避免阴影被拉得很长。
    return mix(1.0,exp(-optical*0.12),fade); // 光学厚度越大透过的直射光越少。
#endif
}
// --- 云的昼夜颜色：三种云共用同一份受光与天气响应 ---
// 调云的受光时只改这里，不会只改到一半；单层、体积、平面云只是基色不同。
vec3 omniCloudColor(vec3 nightColor, vec3 dayColor) {
    float up = omniNormalize(mat3(gbufferModelViewInverse)*sunPosition).y; // 天体方向的世界高度。
    float lit = smoothstep(-0.15,0.1,up); // 天体越接近天顶，云越亮，夜晚自动变暗。
    vec3 color = mix(nightColor,dayColor,lit) * (1.0-rainStrength*0.6); // 雨天把云整体压暗。
    return color * exp(vec3(0.2,0.0,-0.2)*OMNI_CLOUD_TINT); // 冷暖偏移，取零时保持中性。
}
// --- 平面云密度：在水平面上堆三层分形噪声 ---
// 只铺满水平面，不做体积步进，所以云是薄薄一层，看不到厚度。
float omniPlanarDensity(vec2 p) {
    float coverage = omniCloudCoverage(); // 收敛到零到一的云覆盖率。
    if (coverage <= 0.0) return 0.0; // 云量为零时不生成云块，直接跳过后面计算。
    p *= 0.0025; // 米制坐标缩放到云块尺度。
    p += vec2(frameTimeCounter*OMNI_CLOUD_SPEED*0.4,frameTimeCounter*OMNI_CLOUD_SPEED*0.1); // 两个方向不同速度，云缓慢平移。
    float low = omniNoise(vec3(p,0.0))*0.6; // 低频：云块主体。
    float mid = omniNoise(vec3(p*2.7,1.0))*0.3; // 中频：打破整齐。
    float fine = omniNoise(vec3(p*6.1,2.0))*0.1; // 高频：细碎边缘。
    return smoothstep(1.0-coverage,1.0-coverage*0.4,low+mid+fine); // 覆盖率越高成片越连续。
}
// --- 平面云层：射线与云层高度平面求交后着色 ---
vec3 omniPlanarClouds(vec3 color, vec3 direction, float sceneDistance) {
    vec3 d = omniNormalize(direction); // 视线方向。
    if (d.y<0.01) return color; // 视线向下或几乎水平，不会打到头顶的云层。
    float travel = (OMNI_CLOUD_HEIGHT-cameraPosition.y)/d.y; // 视线打到云层平面的距离。
    if (travel<=0.0 || travel>min(sceneDistance,18000.0)) return color; // 云层在身后或超出场景距离就不画。
    vec3 hit = cameraPosition+d*travel; // 视线与云层的交点。
    float density = omniPlanarDensity(hit.xz); // 交点处的云量。
    vec3 cloudColor = omniCloudColor(vec3(0.03,0.04,0.06),vec3(0.9,0.9,0.92)); // 平面云偏亮偏冷。
    float horizon = smoothstep(0.02,0.18,d.y); // 视线越低越淡，避免地平线处出现硬边。
    return mix(color,cloudColor,clamp(density,0.0,1.0)*horizon); // 云量乘以地平线渐隐就是混合权重。
}
// --- 云入口：按模式选择画法 ---
// 单层只采一次密度，体积做多步透射积分，平面走求交；关闭或其他维度直接返回原色。
vec3 omniCloud(vec3 color, vec3 direction, float sceneDistance) {
#if defined OMNI_NETHER || defined OMNI_END
    return color; // 下界与末地没有自定义云，交给各自的天空。
#elif OMNI_CLOUD_MODE == 3
    return omniPlanarClouds(color,direction,sceneDistance); // 平面地平线云层。
#elif OMNI_CLOUD_MODE > 0
    vec3 d = omniNormalize(direction); // 米制步进方向。
    if (abs(d.y) < 0.005) return color; // 视线几乎水平，不与云层相交。
    float lowerCross = (OMNI_CLOUD_HEIGHT - cameraPosition.y) / d.y; // 视线穿过云层下界的距离。
    float upperCross = (OMNI_CLOUD_HEIGHT + 32.0 - cameraPosition.y) / d.y; // 视线穿过云层上界的距离。
    float begin = max(min(lowerCross,upperCross),0.0); // 相机在云层内部时从零开始步进。
    float end = min(max(lowerCross,upperCross),min(sceneDistance,18000.0)); // 步进在地形前或云层上界停下。
    if (end <= begin) return color; // 云在相机身后或被地形挡住，不画。
    float opacity = 0.0; // 累计体积透射损失，零表示完全透明。
#if OMNI_CLOUD_MODE == 1
    opacity = omniCloudDensity(cameraPosition + d * (begin+end) * 0.5) * 0.88; // 单层只采中点一次，省算力。
#else
    float stride = (end-begin)/16.0; // 固定 16 步，步长写死让编译结果可预测。
    for (int i=0;i<16;i++) {
        vec3 p = cameraPosition + d * (begin+(float(i)+0.5)*stride); // 采样点落在每一步的中心。
        float height = (p.y-OMNI_CLOUD_HEIGHT)/32.0; // 相对云层中面的高度，用零到一表示。
        float density = omniCloudDensity(p) * smoothstep(0.0,0.2,height) * (1.0-smoothstep(0.7,1.0,height)); // 上下边缘渐薄，避免云层像一块板。
        opacity += (1.0-opacity) * (1.0-exp(-density*stride*0.07)); // 前向透射积分，后面的采样只影响剩余可见部分。
    }
#endif
    vec3 cloudColor = omniCloudColor(vec3(0.035,0.047,0.07),vec3(0.85,0.86,0.88)); // 体积云偏灰。
    return mix(color,cloudColor,clamp(opacity,0.0,1.0)); // 用不透明度把云混到天空上。
#else
    return color; // 模式为零，编译时移除全部云采样。
#endif
}
#endif
