// 云：天空沿视线与高度层相交，轻量单层或体积步进；示例 omniCloud(color, direction, distance)。
#ifndef OMNI_CLOUD
#define OMNI_CLOUD
// @effect {"label":{"zh_cn":"云","en_us":"Clouds"}}
// @option {"label":{"zh_cn":"云算法","en_us":"Cloud mode"},"description":{"zh_cn":"零关闭，一单层，二体积；体积模式增加沿视线采样。","en_us":"Off, single layer, or ray-marched volume."}}
#define OMNI_CLOUD_MODE 1 // [0 1 2]
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
float omniCloudDensity(vec3 p) {
    p.x += frameTimeCounter * OMNI_CLOUD_SPEED * 2.0; // 风随时间移动噪声。
    float n = 0.5+0.5*(snoise(p * vec3(0.004,0.018,0.004)) * 0.7 + snoise(p * 0.013) * 0.3); // 单纯形梯度噪声降低规则格点痕迹，不宣称未测的性能改善。
    return smoothstep(0.8 - OMNI_CLOUD_COVERAGE * 0.5, 0.95 - OMNI_CLOUD_COVERAGE * 0.5, n); // 覆盖率实际改变密度。
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
vec3 omniCloud(vec3 color, vec3 direction, float sceneDistance) {
#if OMNI_CLOUD_MODE > 0 && !defined OMNI_NETHER && !defined OMNI_END
    vec3 d = omniNormalize(direction); // 米制步进方向。
    if (abs(d.y) < 0.005) return color; // 水平射线不与云层相交。
    float a = (OMNI_CLOUD_HEIGHT - cameraPosition.y) / d.y; // 云层下边界。
    float b = (OMNI_CLOUD_HEIGHT + 32.0 - cameraPosition.y) / d.y; // 云层上边界。
    float begin = max(min(a,b),0.0), end = min(max(a,b),min(sceneDistance,18000.0)); // 地形前停止，支持云层内相机。
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
