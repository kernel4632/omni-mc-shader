// 环境遮蔽与反弹光：读取邻点位置、法线和已照明辐射；示例 omniAmbient(color, view, normal, uv)。
#ifndef OMNI_AMBIENT
#define OMNI_AMBIENT
// @effect {"label":{"zh_cn":"间接照明","en_us":"Indirect light"}}
// @option {"label":{"zh_cn":"屏幕环境遮蔽","en_us":"SSAO"}}
#define OMNI_SSAO
// @option {"label":{"zh_cn":"遮蔽算法","en_us":"AO algorithm"},"description":{"zh_cn":"零用螺旋采样保持旧画面，一用地平线积分更贴合真实遮挡。","en_us":"Zero keeps spiral sampling; one integrates horizons for truer occlusion."}}
#define OMNI_AO_MODE 1 // [0 1]
// @option {"label":{"zh_cn":"屏幕反弹光","en_us":"Screen-space bounce"},"description":{"zh_cn":"仅从屏幕可见邻点辐射估计一次反弹，不是完整全局光。","en_us":"One bounce estimated from visible radiance, not full global illumination."}}
//#define OMNI_SCREEN_BOUNCE
// @option {"label":{"zh_cn":"环境采样半径","en_us":"Ambient radius"}}
#define OMNI_AMBIENT_RADIUS 1.5 // [0.5 1.0 1.5 3.0]
// 坐标与空间随机序列共用。
#include "/common/coordinates.glsl"
#include "/common/math.glsl"
// 判断邻点能否参与邻域采样：屏幕内、有有效几何且不是手或叠层。
bool omniAmbientNeighbor(vec2 sampleUv, out ivec2 samplePixel) {
    if (any(lessThan(sampleUv,vec2(0))) || any(greaterThan(sampleUv,vec2(1))) || omniSkyPixel(sampleUv)) return false; // 屏幕外与天空没有表面。
    samplePixel = clamp(ivec2(sampleUv*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 元数据固定到最近像素。
    return texelFetch(colortex7,samplePixel,0).a>=0.5 && texelFetch(colortex1,samplePixel,0).a!=2.0; // 叠层与手没有可靠屏幕几何。
}
// 螺旋采样环境遮蔽：保留原有固定圆盘采样，供旧画面路径使用。
float omniSpiralOcclusion(vec3 view, vec3 normal, vec2 uv) {
    float occlusion = 0.0, weight = 0.0; // 累计几何遮挡与采样权重。
    float radius = min(0.08,OMNI_AMBIENT_RADIUS/max(-view.z,1.0)); // 米制半径投影到屏幕。
    for (int i=0;i<12;i++) {
        float angle = float(i)*2.399963 + omniHash(floor(uv*vec2(viewWidth,viewHeight)))*6.283185; // 稳定螺旋采样。
        vec2 sampleUv = uv+vec2(cos(angle),sin(angle))*radius*sqrt((float(i)+0.5)/12.0); // 均匀覆盖圆盘。
        ivec2 samplePixel; // 邻点元数据像素。
        if (!omniAmbientNeighbor(sampleUv,samplePixel)) continue; // 无效邻点不参与归一化。
        vec3 delta = omniSceneView(sampleUv,true)-view; // 邻点到当前表面的方向。
        float distance = length(delta); // 米制距离。
        if (distance<0.05 || distance>OMNI_AMBIENT_RADIUS*2.0) continue; // 排除自身与远处无关表面。
        float receiver = max(dot(normal,delta/distance)-0.1,0.0); // 接收表面的半球可见性。
        occlusion += receiver*exp(-distance/OMNI_AMBIENT_RADIUS); // 距离衰减的遮蔽依据。
        weight += 1.0; // 屏幕边缘按有效样本归一化。
    }
    return clamp(occlusion/max(weight,1.0)*1.6,0.0,0.65); // 只压暗，不添加虚构照明。
}
// 地平线邻点余弦：一个屏幕方向上的最大地平线角。
float omniHorizonCosine(vec3 view, vec3 viewDirection, vec2 sampleUv) {
    ivec2 samplePixel; // 邻点元数据像素。
    if (!omniAmbientNeighbor(sampleUv,samplePixel)) return -1.0; // 无效邻点不构成地平线。
    vec3 delta = omniSceneView(sampleUv,true)-view; // 邻点到当前表面的方向。
    float distance = length(delta); // 米制距离。
    if (distance<1e-3 || distance>OMNI_AMBIENT_RADIUS*3.0) return -1.0; // 排除自身与超范围邻点。
    float cosine = dot(delta/distance,viewDirection); // 该邻点的地平线余弦。
    float falloff = clamp(1.0-distance/(OMNI_AMBIENT_RADIUS*3.0),0.0,1.0); // 远处邻点贡献减弱。
    return mix(-1.0,cosine,falloff); // 避免远景几何把画面压黑。
}
// 地平线环境遮蔽：围绕法线切片，按两侧最大地平线角积分半球可见度。
float omniHorizonOcclusion(vec3 view, vec3 normal, vec2 uv) {
    const int slices = 3; // 环绕视线的切片数量。
    const int steps = 6; // 每个方向的地平线搜索步数。
    float phase = omniHash(vec2(gl_FragCoord.xy)); // 每像素稳定相位减少条带。
    vec3 viewDirection = omniNormalize(-view); // 表面指向相机的方向。
    float occlusion = 0.0; // 累计半球可见缺口。
    for (int slice=0;slice<slices;slice++) {
        float sliceAngle = (float(slice)+phase)*3.14159265/float(slices); // 围绕视线均匀分布切片。
        vec3 sliceDirection = vec3(cos(sliceAngle),sin(sliceAngle),0.0); // 切片参考方向。
        vec3 orthogonal = sliceDirection-dot(sliceDirection,viewDirection)*viewDirection; // 正交到视线。
        vec3 axis = cross(sliceDirection,viewDirection); // 切片平面法向。
        vec3 projectedNormal = normal-dot(normal,axis)*axis; // 法线投影到切片平面。
        float normalLength = inversesqrt(max(dot(projectedNormal,projectedNormal),1e-6)); // 投影长度倒数。
        float cosNormalAngle = clamp(dot(projectedNormal,viewDirection)*normalLength,-1.0,1.0); // 投影法线角余弦。
        float normalAngle = sign(dot(orthogonal,projectedNormal))*acos(cosNormalAngle); // 投影法线角。
        float horizonPositive = -1.0, horizonNegative = -1.0; // 两侧最大地平线余弦。
        for (int step=1;step<=steps;step++) {
            float fraction = float(step)/float(steps); // 归一化搜索距离。
            vec2 offset = sliceDirection.xy*fraction*fraction*OMNI_AMBIENT_RADIUS/vec2(viewWidth,viewHeight); // 近密远疏的屏幕偏移。
            horizonPositive = max(horizonPositive,omniHorizonCosine(view,viewDirection,uv+offset)); // 正向搜索。
            horizonNegative = max(horizonNegative,omniHorizonCosine(view,viewDirection,uv-offset)); // 反向搜索。
        }
        float anglePositive = acos(clamp(horizonPositive,-1.0,1.0))*2.0; // 正向地平线角。
        float angleNegative = -acos(clamp(horizonNegative,-1.0,1.0))*2.0; // 反向地平线角。
        occlusion += 2.0*cosNormalAngle+(angleNegative+anglePositive)*sin(normalAngle)-cos(angleNegative-normalAngle)-cos(anglePositive-normalAngle); // 半球可见积分。
    }
    float visibility = occlusion*0.25/float(slices); // 平均可见度。
    return clamp(1.0-clamp(visibility,0.0,1.0),0.0,1.0)*0.65; // 归一化为遮挡系数。
}
// 屏幕反弹光：从可见邻点辐射估计一次漫反射反弹。
vec3 omniBounce(vec3 view, vec3 normal, vec2 uv) {
    vec3 bounce = vec3(0.0); float weight = 0.0; // 只累积实际邻点辐射。
    float radius = min(0.08,OMNI_AMBIENT_RADIUS/max(-view.z,1.0)); // 与螺旋遮蔽一致的屏幕半径。
    for (int i=0;i<12;i++) {
        float angle = float(i)*2.399963 + omniHash(floor(uv*vec2(viewWidth,viewHeight)))*6.283185; // 复用同一稳定采样。
        vec2 sampleUv = uv+vec2(cos(angle),sin(angle))*radius*sqrt((float(i)+0.5)/12.0); // 均匀覆盖圆盘。
        ivec2 samplePixel; // 邻点元数据像素。
        if (!omniAmbientNeighbor(sampleUv,samplePixel)) continue; // 无效邻点不参与反弹。
        vec3 delta = omniSceneView(sampleUv,true)-view; // 邻点到当前表面的方向。
        float distance = length(delta); // 米制距离。
        if (distance<0.05 || distance>OMNI_AMBIENT_RADIUS*2.0) continue; // 排除自身与远处无关表面。
        vec3 direction = delta/distance; // 传播方向归一化。
        float receiver = max(dot(normal,direction)-0.1,0.0); // 接收表面的半球可见性。
        float attenuation = exp(-distance/OMNI_AMBIENT_RADIUS); // 距离衰减。
        vec2 pixel = 1.0/vec2(viewWidth,viewHeight); // 邻点几何必须取同一阶段的数据。
        vec3 target = view+delta; // 当前邻点不透明位置。
        vec3 right = omniSceneView(clamp(sampleUv+vec2(pixel.x,0),0.0,1.0),true); // 邻点水平几何。
        vec3 upper = omniSceneView(clamp(sampleUv+vec2(0,pixel.y),0.0,1.0),true); // 邻点垂直几何。
        vec3 donor = omniNormalize(cross(right-target,upper-target)); // 用不透明深度重建法线。
        if (dot(donor,-target)<0.0) donor = -donor; // 使重建法线朝向可见面。
        bounce += texture(colortex3,sampleUv).rgb*receiver*max(dot(donor,-direction),0.0)*attenuation; // 有方向与辐射输入的单次反弹。
        weight += 1.0; // 按有效样本归一化。
    }
    return bounce/max(weight,1.0)*0.35; // 明确轻量屏幕估计范围。
}
// 环境遮蔽与反弹光入口：按选项选择遮蔽算法，反弹独立累加。
vec3 omniAmbient(vec3 color, vec3 view, vec3 normal, vec2 uv) {
#ifdef OMNI_SSAO
#if OMNI_AO_MODE == 1
    color *= 1.0-omniHorizonOcclusion(view,normal,uv); // 地平线遮挡。
#else
    color *= 1.0-omniSpiralOcclusion(view,normal,uv); // 螺旋遮挡保持旧画面。
#endif
#endif
#ifdef OMNI_SCREEN_BOUNCE
    color += omniBounce(view,normal,uv); // 一次可见反弹。
#endif
    return color; // 关闭两个开关后没有邻点采样。
}
#endif
