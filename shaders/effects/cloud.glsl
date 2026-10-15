// 云：天空沿视线与高度层相交，按模式做单层、体积或平面云，并为直射光提供云影。
// 调用位置：rendering/composite.glsl（几何前遮挡）、rendering/lighting.glsl（天空背景）、effects/sunlight.glsl（云影）。
// 可复制示例：`color = omniCloud(color, omniNormalize(world), length(view));`
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
// 云密度：三维梯度噪声，覆盖率把它映射成 0 到 1 之间的云量。
float omniCloudDensity(vec3 p) {
    float coverage = clamp(OMNI_CLOUD_COVERAGE, 0.0, 1.0); // 越界配置收敛到有效范围。
    p.x += frameTimeCounter * OMNI_CLOUD_SPEED * 2.0; // 风随时间移动噪声。
    float n = 0.5+0.5*(snoise(p * vec3(0.004,0.018,0.004)) * 0.7 + snoise(p * 0.013) * 0.3); // 单纯形梯度噪声降低规则格点痕迹。
    return smoothstep(0.8 - coverage * 0.5, 0.95 - coverage * 0.5, n); // 覆盖率实际改变密度。
}
// 云影透射：从地表沿光线方向步进到云层，按密度估计遮挡。
float omniCloudShadow(vec3 world) {
#if OMNI_CLOUD_SHADOW == 0 || defined OMNI_NETHER || defined OMNI_END
    return 1.0; // 关闭或其他维度不做云影遮挡。
#else
    vec3 sun = omniNormalize(mat3(gbufferModelViewInverse)*shadowLightPosition); // 当前天体世界方向。
    if (sun.y<=0.03) return 1.0; // 天体贴近地平线不产生云影。
    float surfaceY = world.y+cameraPosition.y; // 地表绝对高度。
    float travel = (OMNI_CLOUD_HEIGHT-surfaceY)/sun.y; // 到云层下界的行进距离。
    if (travel<=0.0) return 1.0; // 地表已在云上或光线不向上。
    float optical = 0.0; // 累计云层光学厚度。
    for (int i=0;i<4;i++) {
        vec3 p = world+cameraPosition+sun*travel*((float(i)+0.5)/4.0); // 云层内的采样点。
        optical += omniCloudDensity(p); // 稀疏采样估计密度。
    }
    float fade = smoothstep(0.03,0.15,sun.y); // 低角度淡出避免拉长阴影。
    return mix(1.0,exp(-optical*0.12),fade); // 密度越高直射越暗。
#endif
}
// 平面云密度：在水平面上用三层分形噪声生成连续云块。
float omniPlanarDensity(vec2 p) {
    float coverage = clamp(OMNI_CLOUD_COVERAGE, 0.0, 1.0); // 越界配置收敛到有效范围。
    if (coverage <= 0.0) return 0.0; // 云量为零不生成云块，避免退化区间。
    p *= 0.0025; // 米制坐标缩放到云块尺度。
    p += vec2(frameTimeCounter*OMNI_CLOUD_SPEED*0.4,frameTimeCounter*OMNI_CLOUD_SPEED*0.1); // 风缓慢移动云层。
    float n = omniNoise(vec3(p,0.0))*0.6 + omniNoise(vec3(p*2.7,1.0))*0.3 + omniNoise(vec3(p*6.1,2.0))*0.1; // 三层分形。
    return smoothstep(1.0-coverage,1.0-coverage*0.4,n); // 覆盖率控制连续度。
}
// 平面云层：射线与高度平面相交后按分形密度着色。
vec3 omniPlanarClouds(vec3 color, vec3 direction, float sceneDistance) {
    vec3 d = omniNormalize(direction); // 视线方向。
    if (d.y<0.01) return color; // 向下或水平射线不与云层相交。
    float travel = (OMNI_CLOUD_HEIGHT-cameraPosition.y)/d.y; // 到云层平面的行进距离。
    if (travel<=0.0 || travel>min(sceneDistance,18000.0)) return color; // 受限距离之外或反向。
    vec3 hit = cameraPosition+d*travel; // 平面命中点。
    float density = omniPlanarDensity(hit.xz); // 命中处的云密度。
    float day = smoothstep(-0.15,0.1,omniNormalize(mat3(gbufferModelViewInverse)*sunPosition).y); // 夜间云降低亮度。
    vec3 cloudColor = mix(vec3(0.03,0.04,0.06),vec3(0.9,0.9,0.92),day)*(1.0-rainStrength*0.6); // 雨云变暗。
    cloudColor *= exp(vec3(0.2,0.0,-0.2)*OMNI_CLOUD_TINT); // 云色可独立调整，零值保持中性。
    float horizon = smoothstep(0.02,0.18,d.y); // 地平线附近渐隐避免硬边。
    return mix(color,cloudColor,clamp(density,0.0,1.0)*horizon); // 云层遮挡背景与天空。
}
vec3 omniCloud(vec3 color, vec3 direction, float sceneDistance) {
#if defined OMNI_NETHER || defined OMNI_END
    return color; // 其他维度没有自定义云。
#elif OMNI_CLOUD_MODE == 3
    return omniPlanarClouds(color,direction,sceneDistance); // 平面地平线云层。
#elif OMNI_CLOUD_MODE > 0
    vec3 d = omniNormalize(direction); // 米制步进方向。
    if (abs(d.y) < 0.005) return color; // 水平射线不与云层相交。
    float lowerCross = (OMNI_CLOUD_HEIGHT - cameraPosition.y) / d.y; // 视线穿过云层下界的距离。
    float upperCross = (OMNI_CLOUD_HEIGHT + 32.0 - cameraPosition.y) / d.y; // 视线穿过云层上界的距离。
    float begin = max(min(lowerCross,upperCross),0.0); // 相机在层内时从零开始。
    float end = min(max(lowerCross,upperCross),min(sceneDistance,18000.0)); // 地形前停止。
    if (end <= begin) return color; // 云在相机后或被地形遮挡。
    float opacity = 0.0; // 累计体积透射损失。
#if OMNI_CLOUD_MODE == 1
    opacity = omniCloudDensity(cameraPosition + d * (begin+end) * 0.5) * 0.88; // 轻量路径只采一次密度。
#else
    float stride = (end-begin)/16.0; // 固定采样保证编译可预测。
    for (int i=0;i<16;i++) {
        vec3 p = cameraPosition + d * (begin+(float(i)+0.5)*stride); // 每步位于体积内部。
        float height = (p.y-OMNI_CLOUD_HEIGHT)/32.0; // 高度边缘平滑收束。
        float density = omniCloudDensity(p) * smoothstep(0.0,0.2,height) * (1.0-smoothstep(0.7,1.0,height));
        opacity += (1.0-opacity) * (1.0-exp(-density*stride*0.07)); // 前向透射积分。
    }
#endif
    float day = smoothstep(-0.15,0.1,omniNormalize(mat3(gbufferModelViewInverse)*sunPosition).y); // 夜间云降低亮度。
    vec3 cloudColor = mix(vec3(0.035,0.047,0.07),vec3(0.85,0.86,0.88),day) * (1.0-rainStrength*0.6); // 雨云变暗。
    cloudColor *= exp(vec3(0.2,0.0,-0.2)*OMNI_CLOUD_TINT); // 云色可独立调整，零值保持中性。
    return mix(color,cloudColor,clamp(opacity,0.0,1.0)); // 地形前后由相交距离决定。
#else
    return color; // 关闭与其他维度编译移除云采样。
#endif
}
#endif
