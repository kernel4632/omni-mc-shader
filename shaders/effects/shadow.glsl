// 阴影：阴影入口写深度，光照与雾读取；示例 omniShadow(world, normal)。
// 职责：定义阴影选项、阴影图坐标与遮挡查询（含可变半影），供阴影深度绘制、光照和体积雾共用。
// 调用位置：effects/sunlight.glsl 与 effects/fog.glsl 引入后调用；rendering/shadow.glsl 复用其中选项。
// 可复制示例：`float lit = omniShadow(world, normal); vec3 p = omniShadowCoord(world);`
#ifndef OMNI_SHADOW // 地形与雾共用同一阴影定义。
#define OMNI_SHADOW // 多次引用不重复声明选项与函数。
// @effect {"label":{"zh_cn":"阴影","en_us":"Shadows"}}
// @option {"label": {"zh_cn": "开启阴影", "en_us": "Enable shadows"}, "description": {"zh_cn": "太阳照出的影子开不开。", "en_us": "Whether the sun casts shadows."}}
#define OMNI_SHADOW_ENABLED
// @option {"label": {"zh_cn": "阴影质量", "en_us": "Shadow samples"}, "description": {"zh_cn": "一为单次比较，三或五为柔化采样边长。", "en_us": "One comparison or a three/five wide PCF kernel."}, "values": {"1": {"zh_cn": "低", "en_us": "Low"}, "3": {"zh_cn": "中", "en_us": "Medium"}, "5": {"zh_cn": "高", "en_us": "High"}}}
#define OMNI_SHADOW_QUALITY 3 // [1 3 5]
// @option {"label": {"zh_cn": "阴影柔化", "en_us": "Shadow softness"}, "slider": true, "description": {"zh_cn": "影子边缘软还是硬。", "en_us": "How soft the shadow edges are."}}
#define OMNI_SHADOW_SOFTNESS 1.5 // [0.5 1.0 1.5 2.0 3.0]
// @option {"label":{"zh_cn":"可变半影","en_us":"Variable penumbra"},"description":{"zh_cn":"按遮挡物远近自动调整影子边缘：离得越远影子边越软，贴近时更锐。","en_us":"Widens shadow edges with the distance to the occluder, so far shadows are softer and near ones stay sharp."},"values":{"0":{"zh_cn":"关","en_us":"Off"},"1":{"zh_cn":"开","en_us":"On"}}}
#define OMNI_SHADOW_PENUMBRA 1 // [0 1]
// @option {"label":{"zh_cn":"半影精细度","en_us":"Penumbra detail"},"description":{"zh_cn":"可变半影每像素的采样次数；越高边缘越干净也越耗性能。","en_us":"Samples per pixel for the penumbra; higher is cleaner but costlier."},"values":{"8":{"zh_cn":"低","en_us":"Low"},"16":{"zh_cn":"中","en_us":"Medium"},"24":{"zh_cn":"高","en_us":"High"}}}
#define OMNI_SHADOW_PENUMBRA_QUALITY 16 // [8 16 24]
// @option {"label":{"zh_cn":"阴影模糊","en_us":"Shadow blur"},"description":{"zh_cn":"影子边缘的基础模糊量；调大整体更软，调小更锐。","en_us":"Base blur of the shadow edge; higher is softer overall, lower is sharper."},"slider":true}
#define OMNI_SHADOW_BLUR 1.0 // [0.0 0.5 1.0 1.5 2.0]
// Iris原生阴影常量必须直接使用字面量，菜单范围仍从这两行唯一读取。
// @option {"label": {"zh_cn": "阴影分辨率", "en_us": "Shadow resolution"}, "description": {"zh_cn": "Iris直接读取该原生常量并分配shadowtex。", "en_us": "Iris reads this native constant for shadowtex allocation."}, "values": {"1024": {"zh_cn": "低", "en_us": "Low"}, "2048": {"zh_cn": "中", "en_us": "Medium"}, "4096": {"zh_cn": "高", "en_us": "High"}}}
const int shadowMapResolution = 2048; // [1024 2048 4096]
// @option {"label": {"zh_cn": "阴影距离", "en_us": "Shadow distance"}, "description": {"zh_cn": "Iris直接读取该原生常量并设置阴影范围。", "en_us": "Iris reads this native constant for shadow range."}, "values": {"64.0": {"zh_cn": "近", "en_us": "Near"}, "128.0": {"zh_cn": "中", "en_us": "Medium"}, "192.0": {"zh_cn": "远", "en_us": "Far"}, "256.0": {"zh_cn": "极远", "en_us": "Very far"}}}
const float shadowDistance = 128.0; // [64.0 128.0 192.0 256.0]
// @option {"label":{"zh_cn":"阴影偏置","en_us":"Shadow bias"},"description":{"zh_cn":"比较深度时留出的余量；太小会出现自身条纹，太大会让阴影脱离物体。","en_us":"Depth margin for the comparison; too small causes acne, too large detaches shadows."},"slider":true}
#define OMNI_SHADOW_BIAS 0.0006 // [0.0002 0.0006 0.0012 0.002]
// @option {"label":{"zh_cn":"法线偏移","en_us":"Normal offset"},"description":{"zh_cn":"比较点沿法线抬起的距离，用来减少贴地阴影的自身条纹。","en_us":"Lifts the sample along the normal to reduce self-shadowing on flat surfaces."},"slider":true}
#define OMNI_SHADOW_OFFSET 0.035 // [0.0 0.02 0.035 0.06]
// 共用坐标与归一化。
#include "/common/coordinates.glsl"
#include "/common/math.glsl"
// 相机相对世界位置投向阴影相机，输出零至一的阴影图坐标。
vec3 omniShadowCoord(vec3 world) {
    vec4 clip = shadowProjection * shadowModelView * vec4(world, 1.0); // 世界位置投向阴影相机。
    if (abs(clip.w) < 1e-6) return vec3(-1.0); // 齐次分量退化时返回图外坐标，交给读取者保守回退。
    return clip.xyz / clip.w * 0.5 + 0.5; // 写入者与读取者使用相同无畸变投影。
}
// 阴影可见度：零为全遮蔽，一为无遮蔽；关闭、越界或退化时保守返回一。
// --- 遮挡比较：把柔化与半影的采样收在一处 ---
// 图外一律当作无遮挡：半影采样会跑出阴影图边界，硬读边缘会把边界压成一条黑线。
float omniShadowCompare(vec2 uv, float receiver) {
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return 1.0; // 图外当作照亮。
    return step(receiver, texture(shadowtex0, uv).r); // 采样深度比接收点更远即未遮挡。
}
// --- 可变半影：先估遮挡物平均深度，再按深度差放大柔化半径 ---
// 深度差越大说明遮挡物离接收点越远，影子边缘本该越软；差接近零表示贴着，边缘保持锐利。
// 这是 PCSS 的核心思路，来源见 docs/references.md，按本项目口径重写。
float omniShadowPenumbra(vec2 uv, float receiver, float resolution) {
    const float goldenAngle = 2.39996323; // 黄金角：连续样本自然散开，避免规则条纹。
    float spin = omniHash(uv * resolution) * 6.2831853; // 用阴影图坐标做每像素随机起步角，打散采样图案；顶点阶段也会编译本文件，所以不用 gl_FragCoord。
    float search = OMNI_SHADOW_BLUR * 4.0 / resolution; // 遮挡物搜索半径，随模糊选项缩放。
    float blockerSum = 0.0; // 遮挡物深度累加。
    float blockers = 0.0; // 遮挡物数量。
    float angle = spin; // 从随机角开始旋转。
    for (int i = 0; i < 8; i++) { // 八次样本足够估计平均遮挡深度，代价固定。
        angle += goldenAngle; // 每次按黄金角前进，样本沿螺旋散开。
        float radius = sqrt((float(i) + 0.5) / 8.0) * search; // 面积均匀的螺旋半径。
        vec2 sampleUv = uv + vec2(cos(angle), sin(angle)) * radius; // 当前样本位置。
        bool inside = !any(lessThan(sampleUv, vec2(0.0))) && !any(greaterThan(sampleUv, vec2(1.0))); // 样本是否落在图内。
        float sampleDepth = inside ? texture(shadowtex0, sampleUv).r : 1.0; // 图外深度留最远，不当作遮挡物。
        if (sampleDepth < receiver - OMNI_SHADOW_BIAS) { blockerSum += sampleDepth; blockers += 1.0; } // 只在接收点前面的深度才算遮挡物。
    }
    if (blockers < 0.5) return 1.0; // 附近没有遮挡物，直接视为照亮。
    float avgBlocker = blockerSum / blockers; // 附近遮挡物的平均深度。
    float penumbra = (receiver - avgBlocker) * OMNI_SHADOW_SOFTNESS; // 深度差越大半影越宽。
    float radius = clamp(penumbra + OMNI_SHADOW_BLUR / resolution, OMNI_SHADOW_BLUR * 0.5 / resolution, OMNI_SHADOW_SOFTNESS * 8.0 / resolution); // 下限保证基础模糊，上限避免半径失控。
    float lit = 0.0; // 半影滤波里未遮挡的样本数。
    angle = spin; // 滤波重新从同一随机角起步。
    for (int i = 0; i < OMNI_SHADOW_PENUMBRA_QUALITY; i++) { // 精细度越高边缘越干净。
        angle += goldenAngle; // 样本继续按黄金角散开。
        float sampleRadius = sqrt((float(i) + 0.5) / float(OMNI_SHADOW_PENUMBRA_QUALITY)) * radius; // 面积均匀的滤波半径。
        lit += omniShadowCompare(uv + vec2(cos(angle), sin(angle)) * sampleRadius, receiver); // 累计未遮挡样本。
    }
    return lit / float(OMNI_SHADOW_PENUMBRA_QUALITY); // 未遮挡占比即可见度。
}
float omniShadow(vec3 world, vec3 normal) {
#ifdef OMNI_SHADOW_ENABLED
    float worldDistance = length(world); // 相机相对世界距离，用于覆盖判断与边缘淡出。
    if (worldDistance > shadowDistance * 0.95) return 1.0; // 超出阴影覆盖使用环境照明。
    vec3 n = mat3(gbufferModelViewInverse) * normal; // 视空间法线转世界空间。
    vec3 p = omniShadowCoord(world + n * OMNI_SHADOW_OFFSET); // 法线偏移减少自身条纹，偏移量可调。
    if (any(lessThanEqual(p, vec3(0.0))) || any(greaterThanEqual(p, vec3(1.0)))) return 1.0; // 阴影图外不采样边缘。
    float resolution = max(float(shadowMapResolution), 1.0); // 分辨率退化时采样偏移不会变成无穷。
    float receiver = p.z - OMNI_SHADOW_BIAS; // 比较余量，用来挡住自身条纹。
    float lit; // 未遮蔽占比，由所选路径给出。
#if OMNI_SHADOW_PENUMBRA == 1
    lit = omniShadowPenumbra(p.xy, receiver, resolution); // 可变半影：遮挡物越远边缘越软。
#else
    float result = 0.0; // 固定柔化时累计真实深度比较。
    int kernel = max(OMNI_SHADOW_QUALITY, 1); // 质量退化时至少比较一次。
    for (int y = 0; y < kernel; y++) { // 柔化核纵向覆盖邻近深度。
        for (int x = 0; x < kernel; x++) { // 柔化核横向覆盖邻近深度。
            vec2 offset = (vec2(x, y) - float(kernel - 1) * 0.5) * (OMNI_SHADOW_SOFTNESS + OMNI_SHADOW_BLUR) / resolution; // 柔化核内采样偏移，柔化与模糊共同决定半径。
            result += omniShadowCompare(p.xy + offset, receiver); // 百分比近邻柔化。
        }
    }
    lit = result / float(kernel * kernel); // 未遮蔽采样占比。
#endif
    return mix(lit, 1.0, smoothstep(shadowDistance * 0.8, shadowDistance * 0.95, worldDistance)); // 距离边缘平滑淡出。
#else
    return 1.0; // 关闭时编译移除所有阴影采样。
#endif
}
#endif
