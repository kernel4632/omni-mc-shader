// 屏幕环境遮蔽与反弹光：读取邻点位置、法线和已照明辐射；示例 omniAmbient(color, view, normal, uv)。
#ifndef OMNI_AMBIENT
#define OMNI_AMBIENT
// @effect {"label":{"zh_cn":"间接照明","en_us":"Indirect light"}}
// @option {"label":{"zh_cn":"屏幕环境遮蔽","en_us":"SSAO"}}
#define OMNI_SSAO
// @option {"label":{"zh_cn":"屏幕反弹光","en_us":"Screen-space bounce"},"description":{"zh_cn":"仅从屏幕可见邻点辐射估计一次反弹，不是完整全局光。","en_us":"One bounce estimated from visible radiance, not full global illumination."}}
//#define OMNI_SCREEN_BOUNCE
// @option {"label":{"zh_cn":"环境采样半径","en_us":"Ambient radius"}}
#define OMNI_AMBIENT_RADIUS 1.5 // [0.5 1.0 1.5 3.0]
// 坐标与空间随机序列共用。
#include "/common/coordinates.glsl"
#include "/common/math.glsl"
vec3 omniAmbient(vec3 color, vec3 view, vec3 normal, vec2 uv) {
#if defined OMNI_SSAO || defined OMNI_SCREEN_BOUNCE
    float occlusion = 0.0, weight = 0.0; // 累计几何遮挡与采样权重。
    vec3 bounce = vec3(0); // 只累积实际邻点辐射。
    float radius = min(0.08,OMNI_AMBIENT_RADIUS/max(-view.z,1.0)); // 米制半径投影到屏幕。
    for (int i=0;i<12;i++) {
        float angle = float(i)*2.399963 + omniHash(floor(uv*vec2(viewWidth,viewHeight)))*6.283185; // 稳定螺旋采样。
        vec2 sampleUv = uv+vec2(cos(angle),sin(angle))*radius*sqrt((float(i)+0.5)/12.0); // 均匀覆盖圆盘。
        if (any(lessThan(sampleUv,vec2(0))) || any(greaterThan(sampleUv,vec2(1))) || omniSkyPixel(sampleUv)) continue; // 屏幕外与天空没有表面。
        ivec2 samplePixel = clamp(ivec2(sampleUv*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 邻点元数据固定到最近像素。
        if (texelFetch(colortex7,samplePixel,0).a<0.5 || texelFetch(colortex1,samplePixel,0).a==2.0) continue; // 覆盖层和手没有可靠屏幕几何。
        vec3 delta = omniSceneView(sampleUv,true)-view; // 实际邻点到当前表面的方向。
        float distance = length(delta); // 米制距离。
        if (distance<0.05 || distance>OMNI_AMBIENT_RADIUS*2.0) continue; // 排除自身与远处无关表面。
        vec3 direction = delta/distance; // 传播方向归一化。
        float receiver = max(dot(normal,direction)-0.1,0.0); // 接收表面的半球可见性。
        float attenuation = exp(-distance/OMNI_AMBIENT_RADIUS); // 距离衰减。
        occlusion += receiver*attenuation; // 深度差产生遮蔽依据。
#ifdef OMNI_SCREEN_BOUNCE
        vec2 pixel = 1.0/vec2(viewWidth,viewHeight); // 不透明深度与快照必须取同一阶段的数据。
        vec3 target = view+delta; // 当前邻点不透明位置。
        vec3 right = omniSceneView(clamp(sampleUv+vec2(pixel.x,0),0.0,1.0),true); // 邻点水平几何。
        vec3 upper = omniSceneView(clamp(sampleUv+vec2(0,pixel.y),0.0,1.0),true); // 邻点垂直几何。
        vec3 donor = omniNormalize(cross(right-target,upper-target)); // 用不透明深度重建法线，避免透明元数据与快照错配。
        if (dot(donor,-target)<0.0) donor = -donor; // 使重建法线朝向可见面。
        bounce += texture(colortex3,sampleUv).rgb*receiver*max(dot(donor,-direction),0.0)*attenuation; // 有方向与辐射输入的单次反弹。
#endif
        weight += 1.0; // 屏幕边缘按有效样本归一化。
    }
#ifdef OMNI_SSAO
    color *= 1.0-clamp(occlusion/max(weight,1.0)*1.6,0.0,0.65); // 遮蔽只压暗，不添加虚构照明。
#endif
#ifdef OMNI_SCREEN_BOUNCE
    color += bounce/max(weight,1.0)*0.35; // 明确轻量屏幕估计范围。
#endif
#endif
    return color; // 关闭两个开关后没有邻点采样。
}
#endif
