// 环境遮蔽与物体反光：对已经着色的表面叠加可解释的间接明暗，另含空气补光的接入点。
// 调用位置：由 rendering/composite.glsl 的普通表面后处理显式引用；示例：`color = omniAmbient(color, view, normal, uv);`。
// 可复制示例：
//   `color = omniAmbient(color, omniSceneView(uv,false), normal, uv);`
// 关键取舍：
//   只使用当前屏幕里可见的邻点，屏幕外和背面的表面看不到，缺少信息时不假装知道，宁可少压一点暗。
//   缝隙变暗与物体反光是两条独立开关，都关闭时不采样任何邻点，画面回到没有间接光的原始亮度。
//   缝隙变暗只保留一套地平线积分做法，不再让玩家在算法之间选。
//   空气补光(LPV)只有在明确的计算阶段标志存在时才读取三维纹理；基础 GLSL 330 路径始终保留屏幕空间回退。
#ifndef OMNI_AMBIENT
#define OMNI_AMBIENT
// @effect {"label":{"zh_cn":"环境遮蔽与反弹","en_us":"Indirect light"}}
// @option {"label":{"zh_cn":"缝隙变暗开关","en_us":"Corner darkening"},"description":{"zh_cn":"墙角和方块缝变暗；关掉后这些地方回到没有间接光的样子。","en_us":"Darkens corners and creases; off leaves them without indirect shading."},"page":"shadow"}
#define OMNI_SSAO
// @option {"label":{"zh_cn":"变暗强度","en_us":"Darkening strength"},"slider":true,"page":"shadow"}
#define OMNI_AO_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"变暗范围","en_us":"Darkening range"},"slider":true,"page":"shadow"}
#define OMNI_AMBIENT_RADIUS 1.5 // [0.5 1.0 1.5 3.0]
// @option {"label":{"zh_cn":"变暗方向数","en_us":"Darkening directions"},"description":{"zh_cn":"绕视线检查的遮挡方向数量；越多越稳也越贵。","en_us":"How many directions around the view are checked; more is steadier but costlier."},"page":"shadow"}
#define OMNI_AO_SLICES 3 // [2 3 4]
// @option {"label":{"zh_cn":"变暗精细度","en_us":"Darkening detail"},"description":{"zh_cn":"每个方向搜索遮挡的步数；越多越贴合真实遮挡。","en_us":"Search steps per direction; more matches true occlusion better."},"page":"shadow"}
#define OMNI_AO_STEPS 6 // [4 6 8 12]
// @option {"label":{"zh_cn":"物体反光开关","en_us":"Object bounce"},"description":{"zh_cn":"旁边看得见的物体会把光反到别的表面；只是屏幕里的一次近似，不是完整全局光。","en_us":"Light bouncing from visible nearby surfaces; a screen-space approximation, not full GI."}}
//#define OMNI_SCREEN_BOUNCE
// @option {"label":{"zh_cn":"物体反光强度","en_us":"Bounce strength"},"slider":true}
#define OMNI_BOUNCE_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"物体反光范围","en_us":"Bounce range"},"description":{"zh_cn":"反光能影响多远，越大看到的反弹越多也越贵。","en_us":"How far the bounce reaches; larger sees more bounce and costs more."},"slider":true}
#define OMNI_BOUNCE_RADIUS 1.5 // [0.5 1.0 1.5 3.0]
// 屏幕坐标换算、视空间重建与天空判定由统一坐标模块提供。
#include "/common/coordinates.glsl"
// 归一化与可重复随机数由统一数学模块提供。
#include "/common/math.glsl"
// 逐帧噪声相位由统一抗锯齿模块提供，让遮蔽在时序重建开启时逐帧抖动。
#include "/effects/antialiasing.glsl"
// 空气补光由统一效果主体提供；这里只在明确的计算能力标志下声明纹理，避免读取未写入的三维图像。
#include "/effects/lpv.glsl"
#if defined IRIS_FEATURE_COMPUTE_SHADERS && defined OMNI_LPV_ENABLED
uniform sampler3D omniLpvTex; // 体积格只读采样，实际写入发生在计算阶段。
#endif
// 采样半径边界：用户选项为零或异常时回退到极小正值，后续除法始终安全；变暗与反光各用自己的半径。
const float omniAmbientRadius = max(OMNI_AMBIENT_RADIUS,1e-3);
const float omniBounceRadius = max(OMNI_BOUNCE_RADIUS,1e-3);

// --- 邻点筛选 ---
// 判断一个邻点能否参与邻域采样：必须落在屏幕内、有有效几何，而且不是手或叠层。
bool omniAmbientNeighbor(vec2 sampleUv) {
    // 屏幕外与天空都没有可采样的表面，直接排除。
    if (any(lessThan(sampleUv,vec2(0))) || any(greaterThan(sampleUv,vec2(1))) || omniSkyPixel(sampleUv)) return false;
    // 类别和有效性是离散标记，线性插值会混出并不存在的值，所以固定取最近像素。
    ivec2 samplePixel = omniPixel(sampleUv);
    // 叠层和手没有可靠的屏幕几何，它们的深度不能用来重建邻点位置。
    return texelFetch(colortex7,samplePixel,0).a>=0.5 && texelFetch(colortex1,samplePixel,0).a!=2.0;
}

// --- 屏幕圆盘采样 ---
// 一次螺旋采样在屏幕上的偏移：反光采样用这组角度，位置稳定可复现。
// 为什么按像素哈希旋转：不同像素的样本方向错开，减少规则条纹；同一帧内稳定，不会被时间噪声污染。
vec2 omniSpiralOffset(vec2 uv, float radius, int i) {
    float angle = float(i)*2.399963 + omniHash(floor(uv*vec2(viewWidth,viewHeight)))*6.283185; // 黄金角让相邻样本不重叠。
    return vec2(cos(angle),sin(angle))*radius*sqrt((float(i)+0.5)/12.0); // 开方让样本均匀铺满圆盘。
}

// --- 地平线环境遮蔽 ---
// 地平线样本：某个屏幕方向上邻点给出的地平线余弦，返回 `x` 为余弦、`y` 为是否有有效遮挡证据。
// 为什么把“余弦”和“有没有样本”分成两个分量：无有效邻点不等于“地平线压到最低”。旧写法用负一
// 同时兼任余弦和“没有样本”，两种含义分不开，孤立几何或天空边界上会累积出最强遮挡，把画面压暗到上限。
vec2 omniHorizon(vec3 view, vec3 viewDirection, vec2 sampleUv) {
    if (!omniAmbientNeighbor(sampleUv)) return vec2(0.0,0.0); // 无效邻点不构成地平线，也没有证据。
    vec3 delta = omniSceneView(sampleUv,true)-view; // 邻点相对当前表面的方向。
    float distance = length(delta); // 米制距离。
    if (distance<1e-3 || distance>omniAmbientRadius*3.0) return vec2(0.0,0.0); // 太近是自身，太远不参与地平线。
    float cosine = dot(delta/distance,viewDirection); // 邻点方向与视线方向的夹角余弦。
    float falloff = clamp(1.0-distance/(omniAmbientRadius*3.0),0.0,1.0); // 越远贡献越弱，避免远景把画面压黑。
    return vec2(mix(-1.0,cosine,falloff),1.0); // 有效样本给出余弦，衰减到零也仍算有证据。
}
// 一个切片方向上的半球可见缺口：把法线投到切片平面，向两侧搜索最大地平线，再积分这一段遮挡。
// 两侧都没有有效样本时返回零，表示这一片没有遮挡证据，不参与累加，绝不能当成最强遮挡。
float omniSliceOcclusion(vec3 view, vec3 viewDirection, vec3 normal, vec2 uv, float sliceAngle) {
    const int steps = OMNI_AO_STEPS; // 每个方向的地平线搜索步数，可调，越多越贴合真实遮挡。
    vec3 sliceDirection = vec3(cos(sliceAngle),sin(sliceAngle),0.0); // 切片在屏幕平面里的方向。
    vec3 orthogonal = sliceDirection-dot(sliceDirection,viewDirection)*viewDirection; // 切片方向正交到视线的分量。
    vec3 axis = cross(sliceDirection,viewDirection); // 切片平面的法向，用来把法线投影进来。
    vec3 projectedNormal = normal-dot(normal,axis)*axis; // 法线投影到切片平面，得到二维遮挡几何。
    float normalLength = inversesqrt(max(dot(projectedNormal,projectedNormal),1e-6)); // 投影长度的倒数，几乎为零时也不会除零。
    float cosNormalAngle = clamp(dot(projectedNormal,viewDirection)*normalLength,-1.0,1.0); // 投影法线相对视线的夹角余弦。
    float normalAngle = sign(dot(orthogonal,projectedNormal))*acos(cosNormalAngle); // 带符号的法线角，区分切片的左右两侧。
    float horizonPositive = -1.0, horizonNegative = -1.0; // 两侧搜索到的最大地平线余弦，未找到时保持开口值。
    bool found = false; // 这一片是否找到过任何有效遮挡证据。
    for (int step=1;step<=steps;step++) {
        float fraction = float(step)/float(steps); // 归一化搜索距离。
        vec2 offset = sliceDirection.xy*fraction*fraction*omniAmbientRadius/vec2(viewWidth,viewHeight); // 近密远疏的屏幕偏移。
        vec2 positive = omniHorizon(view,viewDirection,uv+offset); // 正向搜索地平线。
        vec2 negative = omniHorizon(view,viewDirection,uv-offset); // 反向搜索地平线。
        if (positive.y>0.0) { horizonPositive = max(horizonPositive,positive.x); found = true; } // 有证据才更新这一侧。
        if (negative.y>0.0) { horizonNegative = max(horizonNegative,negative.x); found = true; } // 另一侧同理。
    }
    if (!found) return 0.0; // 没有任何邻点，这一片不产生遮挡，避免把“没有证据”当成“最大遮挡”。
    float anglePositive = acos(clamp(horizonPositive,-1.0,1.0))*2.0; // 正向地平线对应的开口角。
    float angleNegative = -acos(clamp(horizonNegative,-1.0,1.0))*2.0; // 反向地平线对应的开口角。
    return 2.0*cosNormalAngle+(angleNegative+anglePositive)*sin(normalAngle)-cos(angleNegative-normalAngle)-cos(anglePositive-normalAngle); // 这一段切片的半球可见缺口。
}
// 缝隙变暗：绕视线均匀切片，累加每个切片方向的可见缺口，得到整个半球被挡住的比重。
float omniHorizonOcclusion(vec3 view, vec3 normal, vec2 uv) {
    const int slices = OMNI_AO_SLICES; // 环绕视线的切片数量，可调，越多越稳但越贵。
#if defined OMNI_ANTIALIASING && defined OMNI_AA_ENABLED && OMNI_TEMPORAL_DENOISE == 1
    float phase = omniTemporalNoise(vec2(gl_FragCoord.xy)); // 时间抗锯齿开启时逐帧旋转，历史帧重建去噪。
#else
    float phase = omniHash(vec2(gl_FragCoord.xy)); // 没有时间重建时保持空间稳定。
#endif
    vec3 viewDirection = omniNormalize(-view); // 从表面指向相机的方向。
    float occlusion = 0.0; // 累计各切片的半球可见缺口。
    for (int slice=0;slice<slices;slice++) {
        float sliceAngle = (float(slice)+phase)*3.14159265/float(slices); // 把切片围绕视线均匀分布。
        occlusion += omniSliceOcclusion(view,viewDirection,normal,uv,sliceAngle); // 累加这一个切片方向。
    }
    float visibility = occlusion*0.25/float(slices); // 平均到每个切片，得到半球可见度。
    return clamp(1.0-clamp(visibility,0.0,1.0),0.0,1.0)*0.65; // 转成遮挡系数并封顶，只压暗。
}

// --- 物体反光 ---
// 用邻点四周的不透明深度重建该邻点的表面法线：屏幕没有直接给出邻点法线，而反光需要知道它朝哪。
vec3 omniDonorNormal(vec3 target, vec2 sampleUv) {
    vec2 pixel = 1.0/vec2(viewWidth,viewHeight); // 取邻点几何要和当前阶段用同一份数据。
    vec3 right = omniSceneView(clamp(sampleUv+vec2(pixel.x,0),0.0,1.0),true); // 邻点水平方向的几何位置。
    vec3 upper = omniSceneView(clamp(sampleUv+vec2(0,pixel.y),0.0,1.0),true); // 邻点垂直方向的几何位置。
    vec3 donor = omniNormalize(cross(right-target,upper-target)); // 相邻两点叉乘重建表面法线。
    if (dot(donor,-target)<0.0) donor = -donor; // 使重建法线朝向可见面。
    return donor;
}
// 物体反光：从屏幕里可见的邻点辐射估计一次漫反射反弹，只是轻量近似，不是完整全局光。
vec3 omniBounce(vec3 view, vec3 normal, vec2 uv) {
    vec3 bounce = vec3(0.0); float weight = 0.0; // 累计反弹颜色与有效样本数。
    float radius = min(0.08,omniBounceRadius/max(-view.z,1.0)); // 用反光范围换算屏幕半径，并设上限避免近处摊得过大。
    for (int i=0;i<12;i++) {
        vec2 sampleUv = uv+omniSpiralOffset(uv,radius,i); // 圆盘样本。
        if (!omniAmbientNeighbor(sampleUv)) continue; // 无效邻点不参与反光。
        vec3 delta = omniSceneView(sampleUv,true)-view; // 邻点相对当前表面的方向。
        float distance = length(delta); // 米制距离。
        if (distance<0.05 || distance>omniBounceRadius*2.0) continue; // 太近是自身，太远与当前点无关。
        vec3 direction = delta/distance; // 沿邻点方向的传播方向。
        float receiver = max(dot(normal,direction)-0.1,0.0); // 当前表面朝向邻点才接收反光。
        float attenuation = exp(-distance/omniBounceRadius); // 距离越远反光越弱。
        vec3 donor = omniDonorNormal(view+delta,sampleUv); // 邻点表面法线决定它往哪反。
        bounce += texture(colortex3,sampleUv).rgb*receiver*max(dot(donor,-direction),0.0)*attenuation; // 有方向与辐射输入的单次反光。
        weight += 1.0; // 记录一个有效样本。
    }
    return bounce/max(weight,1.0)*0.35; // 平均后按轻量系数返回，避免屏幕估计过亮。
}

// --- 入口 ---
// 缝隙变暗、物体反光与空气补光各自独立叠加，返回修改后的颜色。
vec3 omniAmbient(vec3 color, vec3 view, vec3 normal, vec2 uv) {
#ifdef OMNI_SSAO
    color *= 1.0-clamp(omniHorizonOcclusion(view,normal,uv)*OMNI_AO_STRENGTH,0.0,1.0); // 缝隙变暗；强度选项整体放大或缩小。
#endif
#ifdef OMNI_SCREEN_BOUNCE
    color += omniBounce(view,normal,uv)*OMNI_BOUNCE_STRENGTH; // 屏幕里可见的一次反光，强度可调。
#endif
#if defined IRIS_FEATURE_COMPUTE_SHADERS && defined OMNI_LPV_ENABLED
    color += omniLpvSample(omniLpvTex,omniWorld(view)) * OMNI_LPV_STRENGTH; // 只有计算路径确认存在时才叠加空气补光，避免基础路径读未写入纹理。
#else
    // 没有可靠的计算能力标志时不猜测三维纹理状态，保留上面的反光或无 LPV 原色路径。
#endif
    return color; // 两个开关都关闭时没有邻点采样，颜色不变。
}
#endif
