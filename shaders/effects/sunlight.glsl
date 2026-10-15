// 职责：直接光、环境光与方块光的统一照明，地形、实体、透明物与远景共用同一份计算。
// 调用位置：rendering/terrain.glsl 与 rendering/distant.glsl 的片元阶段按需引入。
// 可复制示例：`vec3 lit = omniLighting(albedo, normal, world, lightUv, materialParams, materialAo);`
#ifndef OMNI_SUNLIGHT
#define OMNI_SUNLIGHT
// @effect {"label":{"zh_cn":"光照","en_us":"Lighting"}}
// @option {"label": {"zh_cn": "阳光强度", "en_us": "Sunlight strength"}, "slider": true, "description": {"zh_cn": "白天太阳多亮。", "en_us": "How bright the direct sunlight is."}}
#define OMNI_SUNLIGHT_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"阳光色温","en_us":"Sunlight tint"},"description":{"zh_cn":"正值偏暖、负值偏冷，零保持中性；只改直射光颜色不改强度。","en_us":"Positive warms the direct light, negative cools it, zero stays neutral; strength is unchanged."},"slider":true}
#define OMNI_SUN_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label": {"zh_cn": "环境光强度", "en_us": "Ambient light strength"}, "slider": true, "description": {"zh_cn": "阴影里多亮。", "en_us": "How bright shaded areas are."}}
#define OMNI_AMBIENT_STRENGTH 1.0 // [0.25 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"环境光色温","en_us":"Ambient light tint"},"description":{"zh_cn":"正值背光偏暖、负值偏冷，零保持中性。","en_us":"Positive warms the shadowed light, negative cools it, zero stays neutral."},"slider":true}
#define OMNI_AMBIENT_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"天光强度","en_us":"Skylight strength"},"description":{"zh_cn":"环境光里来自天空那一份的占比；调高阴影偏蓝亮，调低更接近灰暗。与阳光强度相互独立。","en_us":"Share of ambient that comes from the sky; higher is a bluer shaded look, lower is flatter grey. Independent from sunlight strength."},"slider":true}
#define OMNI_SKYLIGHT_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"夜间亮度","en_us":"Night brightness"},"description":{"zh_cn":"夜里月光与夜空的亮度倍率；调低夜晚更暗更真实，调高看得更清。白天不受影响。","en_us":"Brightness multiplier for moonlight and the night sky; lower is darker and more realistic, higher is easier to see. Daytime is unaffected."},"slider":true}
#define OMNI_NIGHT_BRIGHTNESS 0.5 // [0.0 0.25 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"无光亮度","en_us":"No-light brightness"},"description":{"zh_cn":"洞穴深处这类既没阳光也没火把的地方的最低亮度；取零会完全变黑。","en_us":"Floor brightness where there is neither sunlight nor torch light, such as deep caves; zero goes fully black."},"slider":true}
#define OMNI_NOLIGHT_BRIGHTNESS 0.5 // [0.0 0.25 0.5 1.0 2.0]
// @option {"label": {"zh_cn": "火把光强度", "en_us": "Torch light strength"}, "slider": true, "description": {"zh_cn": "火把照亮范围多亮。", "en_us": "How bright block light is."}}
#define OMNI_BLOCKLIGHT_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"火把光色温","en_us":"Torch light tint"},"description":{"zh_cn":"正值更暖、负值更冷，零保持默认暖色；只改方块光颜色。","en_us":"Positive warms the block light, negative cools it, zero keeps the default warm tone."},"slider":true}
#define OMNI_BLOCKLIGHT_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"方向性方块光","en_us":"Directional block light"},"description":{"zh_cn":"让方块光按表面朝向光的方向略微变亮，光照更立体；主要在有凹凸贴图的表面上看得出。","en_us":"Brightens surfaces facing the light so block light reads as directional; most visible on bumpy textured surfaces."},"values":{"0":{"zh_cn":"关","en_us":"Off"},"1":{"zh_cn":"开","en_us":"On"}}}
#define OMNI_DIRECTIONAL_BLOCKLIGHT 1 // [0 1]
// @option {"label":{"zh_cn":"方向性强度","en_us":"Directional strength"},"description":{"zh_cn":"方向性方块光的作用强度；越大越立体，取零等于关闭。","en_us":"How strong the directional effect is; higher is more sculpted, zero disables it."},"slider":true}
#define OMNI_DIRECTIONAL_BLOCKLIGHT_STRENGTH 0.5 // [0.1 0.2 0.3 0.5 0.7 1.0]
// @option {"label": {"zh_cn": "手持光开关", "en_us": "Held light"}, "description": {"zh_cn": "手里拿着光源会不会照亮周围。", "en_us": "Whether a held light lights the surroundings."}}
#define OMNI_HELD_LIGHT
// @option {"label": {"zh_cn": "手持光亮度", "en_us": "Held light strength"}, "slider": true, "description": {"zh_cn": "手持光多亮。", "en_us": "How bright the held light is."}}
#define OMNI_HELD_BRIGHTNESS 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"手持光模式","en_us":"Held light mode"},"description":{"zh_cn":"点光：以玩家为中心向四周照亮；手电筒：朝视线方向打出一束锥形光。","en_us":"Point: lights around the player; Flashlight: a cone aimed along the view."},"values":{"0":{"zh_cn":"点光","en_us":"Point"},"1":{"zh_cn":"手电筒","en_us":"Flashlight"}}}
#define OMNI_HELDLIGHT_MODE 0 // [0 1]
// @option {"label":{"zh_cn":"手持光遮挡","en_us":"Held light shadow"},"description":{"zh_cn":"墙和物体挡住手持光时，它们背后会不会变暗。","en_us":"Whether walls and objects block the held light and darken what is behind them."},"values":{"0":{"zh_cn":"关","en_us":"Off"},"1":{"zh_cn":"开","en_us":"On"}}}
#define OMNI_HELDLIGHT_SHADOW 1 // [0 1]
// @option {"label": {"zh_cn": "镜面高光", "en_us": "Specular highlights"}, "description": {"zh_cn": "GGX 分布与施利克菲涅耳提供直射镜面，粗糙度和金属来自材质。", "en_us": "GGX distribution with Schlick Fresnel for direct specular, driven by material roughness and metal."}, "values": {"0": {"zh_cn": "关", "en_us": "Off"}, "1": {"zh_cn": "开", "en_us": "On"}}}
#define OMNI_SPECULAR 1 // [0 1]
// @option {"label":{"zh_cn":"自发光亮度","en_us":"Emissiveness brightness"},"description":{"zh_cn":"发光方块自己有多亮；越大越容易过曝。","en_us":"How bright emissive blocks are; higher is more prone to blowing out."},"slider":true}
#define OMNI_EMISSIVENESS_BRIGHTNESS 1.0 // [0.25 0.5 1.0 2.0 4.0 8.0]
// @option {"label":{"zh_cn":"自发光伽马","en_us":"Emissiveness gamma"},"description":{"zh_cn":"自发光亮度的曲线；大于一压暗中间亮度。","en_us":"Curve of emissive brightness; above one darkens midtones."},"slider":true}
#define OMNI_EMISSIVENESS_GAMMA 1.0 // [0.5 1.0 1.5 2.2]
// 阴影与环境输入只有共同来源。
#include "/effects/shadow.glsl"
// 云影需要云密度，主世界直射光按云层衰减。
#include "/effects/cloud.glsl"
// 镜面高光：GGX 法线分布、施利克菲涅耳与 Smith 可见性，输入来自材质的粗糙度和金属。
// 反射率口径与 effects/reflection.glsl 一致：labPBR 绿色通道在二百三十以下直接存非金属反射率，
// 没有材质包时地形默认零点零四、水是零点零二；二百三十及以上表示金属，金属的反射色就是它的底色。
// 返回值已经是高光亮度本身，调用方不能再乘底色，否则深色方块没有高光、非金属高光也会被染色。
// 法线或光方向退化时归一化返回零向量，镜面随之收敛为零，不产生 NaN。
vec3 omniSpecular(vec3 albedo, vec3 normal, vec3 world, vec3 materialParams, vec3 sun, float shadow) {
    vec3 n = omniNormalize(mat3(gbufferModelViewInverse)*normal); // 世界空间法线。
    vec3 l = omniNormalize(mat3(gbufferModelViewInverse)*sun); // 世界空间光方向。
    vec3 v = omniNormalize(-world); // 表面指向相机，相机处退化为零向量。
    vec3 h = omniNormalize(l+v); // 半程向量。
    float roughness = clamp(materialParams.x,0.05,1.0); // 粗糙度下限避免除零，上限防止分布发散。
    float alpha = roughness*roughness; // GGX 粗糙参数。
    float nh = max(dot(n,h),0.0); // 法线与半程向量夹角余弦。
    float nl = max(dot(n,l),0.0); // 法线与光方向夹角余弦，下半球法线在此收敛为零。
    float nv = max(dot(n,v),1e-4); // 法线与视线夹角余弦，保留非零下限。
    float denom = nh*nh*(alpha*alpha-1.0)+1.0; // 法线分布分母，恒不小于 alpha 平方。
    float distribution = alpha*alpha/(3.14159265*denom*denom); // GGX 法线分布。
    float metal = step(230.0/255.0,materialParams.y); // 材质标准约定的金属标记。
    vec3 f0 = mix(vec3(clamp(materialParams.y,0.0,1.0)),clamp(albedo,0.0,1.0),metal); // 非金属用材质反射率，金属用底色。
    vec3 fresnel = f0+(1.0-f0)*pow(1.0-max(dot(h,v),0.0),5.0); // 施利克近似。
    float k = alpha*0.5; // Smith 可见性参数，恒为正。
    float visibility = (nv/(nv*(1.0-k)+k))*(nl/(nl*(1.0-k)+k)); // 几何可见性，分母由 k 保证不为零。
    return distribution*fresnel*visibility*nl*shadow; // 返回高光亮度与阴影。
}
// 用一份色温偏移乘到光色上：正值偏暖（加红减蓝），负值偏冷（减红加蓝），零保持中性。
// 只让红蓝反向移动，绿色不动，避免调整色温时整体亮度变化；振幅固定，选项只控制方向与幅度。
vec3 omniTint(float amount) {
    return vec3(1.0+0.25*amount,1.0,1.0-0.25*amount); // 零偏移返回全一，等于不改颜色。
}
// 方向性方块光：按方块光在表面上的变化方向，让朝光的一面略亮、背光的一面略暗，光照更有立体感。
// iterationT 的做法是把方块光等级在屏幕上的梯度，经切线基还原成一个沿表面的世界方向，再和表面法线比较。
// 这里用世界位置的两条屏幕导数还原同一个方向，不依赖纹理切线基；平坦表面的梯度落在切平面内、点乘接近零，
// 所以效果主要出现在有凹凸贴图的表面，和参考行为一致。越暗的地方方向感越强，也是参考的口径。
float omniDirectionalBlock(float level, vec3 normal, vec3 world, vec2 light) {
#ifdef OMNI_DIRECTIONAL_BLOCKLIGHT
    vec2 gradient = vec2(dFdx(light.x), dFdy(light.x)); // 方块光等级在屏幕横纵方向的斜率。
    if (dot(gradient, gradient) < 1e-10) return level; // 均匀受光面没有方向，原样返回。
    vec3 alongU = dFdx(world); // 屏幕横向对应的世界位移。
    vec3 alongV = dFdy(world); // 屏幕纵向对应的世界位移。
    vec3 toLight = omniNormalize(alongU * gradient.x + alongV * gradient.y); // 沿表面指向更亮处的世界方向。
    vec3 worldNormal = omniNormalize(mat3(gbufferModelViewInverse) * normal); // 表面法线转到世界空间。
    float facing = dot(toLight, worldNormal); // 越朝向光越接近一，背光为负。
    float weight = 1.0 + OMNI_DIRECTIONAL_BLOCKLIGHT_STRENGTH * facing * (1.0 - level * 0.95); // 越暗方向感越强。
    return clamp(level * weight, 0.0, 0.9999); // 收敛到有效等级，不超过满亮。
#else
    return level; // 关闭时不计算导数，编译移除这一支。
#endif
}
// 手持光遮挡：光源就在相机上，屏幕空间里比射线更靠近相机的几何，就是挡住光的东西。
// 做法：从表面沿法线抬离一点，向相机方向走几小步；每步读屏幕深度，若那一点的几何比脚步更靠近相机，判定被挡住。
// 为什么抬离表面：贴着表面起步会把表面自己当成遮挡物，出现整片自遮挡。
// 为什么只在开启时计算的调用方负责：本函数不做开关判断，调用方用编译分支控制，关闭时整段不编译。
float omniHeldShadow(vec3 view, vec3 normal) {
    vec3 start = view + omniNormalize(normal) * 0.05; // 沿法线抬离表面，避免自遮挡。
    vec3 end = view * 0.06; // 走到相机附近就停下。
    const int steps = 8; // 固定步数，保证开销可预期。
    float shadow = 1.0; // 默认未被遮挡。
    for (int i = 1; i <= steps; i++) {
        vec3 pos = mix(start, end, float(i) / float(steps)); // 沿射线均匀取样。
        vec3 screen = omniProject(pos); // 取样的屏幕坐标与深度。
        if (any(lessThan(screen.xy, vec2(0.0))) || any(greaterThan(screen.xy, vec2(1.0)))) break; // 跑出画面就不再判断。
        float sceneDepth = texture(depthtex1, screen.xy).r; // 该像素不透明几何的深度。
        if (sceneDepth >= 1.0) continue; // 天空没有实体，跳过。
        float sceneZ = omniView(screen.xy, sceneDepth).z; // 还原成视空间深度。
        if (sceneZ > pos.z + 0.03) { shadow = 0.0; break; } // 更靠近相机的几何挡住了光。
    }
    return mix(shadow, 1.0, 0.15); // 留一点底光，避免被遮处全黑。
}
// 调用位置：rendering/terrain.glsl和rendering/distant.glsl；示例：omniLighting(albedo, normal, world, lightUv, materialParams, materialAo)。
vec3 omniLighting(vec3 albedo, vec3 normal, vec3 world, vec2 light, vec3 materialParams, float materialAo) {
    vec3 sun = omniNormalize(shadowLightPosition); // 当前阴影天体可为太阳或月亮；退化时为零向量，直接光收敛为零。
    float sunUpDot = dot(omniNormalize(sunPosition), omniNormalize(upPosition)); // 天体与天顶方向的夹角关系。
    float day = smoothstep(-0.15, 0.1, sunUpDot); // 黎明平滑过渡。
    // 直接把太阳和月亮的能量分开列出来：夜间亮度只压夜间这一端，白天完全不受它影响。
    vec3 sunDirect = vec3(1.4,1.23,1.0); // 太阳的直射能量与偏暖色。
    vec3 moonDirect = vec3(0.16,0.22,0.34) * OMNI_NIGHT_BRIGHTNESS; // 月光的直射能量与偏冷色，随夜间亮度整体缩放。
    vec3 direct = mix(moonDirect, sunDirect, day) * omniTint(OMNI_SUN_TINT); // 日月能量合并；色温选项整体偏暖或偏冷。
    float sky = pow(clamp(light.y, 0.0, 1.0), 2.0); // 原版天空光限制洞穴中的天体照明。
    // 天光：天空可见时受到的蓝色环境光，同样随昼夜变化，并随夜间亮度变暗。
    vec3 skyLight = mix(vec3(0.035,0.047,0.075) * OMNI_NIGHT_BRIGHTNESS, vec3(0.24,0.32,0.43), day) * sky;
    // 无光地板：既没有天光也没有方块光时的最低亮度，靠它让洞穴不是纯黑；取零表示允许完全黑。
    vec3 noLight = vec3(0.02,0.022,0.03) * OMNI_NOLIGHT_BRIGHTNESS;
    float blockLevel = omniDirectionalBlock(clamp(light.x, 0.0, 1.0), normal, world, light); // 方向性方块光：朝光略亮。
    float block = pow(blockLevel, 3.0); // 方块光保留局部衰减。
#ifdef OMNI_HELD_LIGHT
    float held = float(max(heldBlockLightValue, heldBlockLightValue2)) / 15.0; // 双手取实际较亮光源，没拿光源时为零。
    float heldLight = 0.0; // 没拿光源就不计算，省下衰减与遮挡的开销。
    if (held > 0.0) {
        float heldDist = length(world); // 表面离相机（也就是光源）的距离，单位米。
#if OMNI_HELDLIGHT_MODE == 1
        vec3 aim = omniNormalize(mat3(gbufferModelViewInverse) * vec3(0.0, 0.0, -1.0)); // 相机看向的世界方向。
        vec3 toSurface = omniNormalize(world); // 从相机指向表面的方向。
        float cone = smoothstep(0.6, 0.9, dot(toSurface, aim)); // 锥形范围：越靠视线中心越亮。
        heldLight = held * cone * max(1.0 - heldDist / 24.0, 0.0); // 手电筒：锥形加距离衰减。
#else
        float fade = max(1.0 - heldDist / 16.0, 0.0); // 点光：以相机为中心的球形衰减。
        heldLight = held * fade * fade; // 平方让边缘更柔和。
#endif
#if OMNI_HELDLIGHT_SHADOW == 1
        heldLight *= omniHeldShadow(mat3(gbufferModelView) * world, normal); // 被墙或物体挡住时变暗；视空间位置由相机矩阵还原。
#endif
        block = max(block, heldLight * OMNI_HELD_BRIGHTNESS); // 亮度可调，不声称任意彩色动态光源。
    }
#endif
    // 环境光底色：主世界是「天光按天光强度取一份，再加无光地板」，天光与环境光强度分离控制；
    // 下界与末地没有真实天空，直接给一组维度底色，再统一乘环境光强度与色温。
    vec3 ambient = skyLight * OMNI_SKYLIGHT_STRENGTH + noLight;
#if defined OMNI_NETHER
    ambient = vec3(0.16,0.065,0.04); // 下界无太阳，使用维度环境光。
    direct *= 0.0; // 下界不保留主世界天体照明。
#elif defined OMNI_END
    ambient = vec3(0.13,0.09,0.18); // 末地冷紫环境光。
    direct *= 0.0; // 末地不使用主世界日月。
#endif
    ambient *= OMNI_AMBIENT_STRENGTH * omniTint(OMNI_AMBIENT_TINT); // 环境光总强度与色温，取零保持中性。
    float shadow = 1.0; // 其他维度或关闭阴影时直接光不被遮挡。
#if !defined OMNI_NETHER && !defined OMNI_END
    shadow = omniShadow(world, normal); // 主世界直接光和阴影共同控制亮面。
#endif
    float diffuse = max(dot(normal, sun), 0.0) * shadow; // 没有直接光的维度不读取阴影图；下半球法线或退化光方向在此收敛为零。
    float cloudShade = 1.0; // 没有云影时直射光不变。
#if OMNI_CLOUD_SHADOW == 1 && !defined OMNI_NETHER && !defined OMNI_END
    cloudShade = omniCloudShadow(world); // 云影同时衰减漫反射与镜面。
#endif
    // 云影也压一点天光：云挡住太阳时整片环境光同样略暗，比只压直射光更接近真实；云影关闭时 cloudShade 恒为一，这一步等于没做。
    ambient *= mix(1.0, cloudShade, OMNI_CLOUD_SHADOW_AMBIENT); // 影响程度由选项控制，取零只压直射光。
    vec3 lightColor = ambient * materialAo + vec3(0.012) * OMNI_AMBIENT_STRENGTH + vec3(1.15,0.55,0.20) * omniTint(OMNI_BLOCKLIGHT_TINT) * block * OMNI_BLOCKLIGHT_STRENGTH; // 环境光已含总强度，这里只补一份随强度缩放的基底；材质遮蔽只压低环境光，不削弱直接光；方块光颜色与强度可调。
    float weather = 1.0 - rainStrength * 0.65; // 雨天统一压低直射能量，漫反射与镜面共用。
    float metal = step(230.0/255.0, materialParams.y); // 金属不产生直射漫反射，直射光只以高光形式出现。
    lightColor += direct * diffuse * sky * weather * OMNI_SUNLIGHT_STRENGTH * cloudShade * (1.0 - metal); // 直射漫反射；环境光与方块光仍保留，近似金属对周围环境的反光。
    lightColor = mix(lightColor, max(lightColor, vec3(0.65)), nightVision); // 保留夜视能力。
    vec3 specular = vec3(0.0); // 关闭高光时为零。
#if OMNI_SPECULAR == 1
    specular = omniSpecular(albedo,normal,world,materialParams,sun,shadow) * direct * sky * weather * OMNI_SUNLIGHT_STRENGTH * cloudShade; // 直射镜面高光，颜色已经包含在反射率里。
#endif
    return albedo * lightColor + specular + pow(max(albedo,vec3(0.0)),vec3(max(OMNI_EMISSIVENESS_GAMMA,0.1))) * materialParams.z * OMNI_EMISSIVENESS_BRIGHTNESS; // 漫反射乘底色，高光单独相加；自发光按亮度与伽马可调，默认不再四倍过曝。
}
#endif
