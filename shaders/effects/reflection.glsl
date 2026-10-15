/*
屏幕空间反射：在屏幕里沿反射方向去找被反射到的几何，找不到就回退成天空色，屏幕反射默认关闭。
调用位置：rendering/composite.glsl 的普通与湿润表面，以及 effects/water.glsl 的水面反射。
可复制示例：
  `vec3 lit = omniReflection(color, view, normal, materialParams, uv);`  底色与反射合成的最终颜色
  `vec3 env = omniReflected(view, normal, 0.06);`                        只要反射部分时（水面这样用）

它做什么：给一个表面，返回这个表面照到的颜色，三件事按顺序发生——
  一、先算一份天空环境色，作为屏幕外和被遮挡时的底；
  二、隔着屏幕沿反射方向一步步往前走，撞到不透明几何就取那里的屏幕颜色；
  三、按菲涅耳比例把底色和反射混合，越接近掠射角反射越强。

为什么这样设计（取舍）：
  - 屏幕反射只能照到屏幕里已经画出来的东西，屏幕外和被挡住的内容它看不到，
    所以必须有天空回退，否则这些地方会变成黑洞。
  - 近景和远景各自有独立的投影和深度缓冲，把一方的位置拿去另一方采样会得到错误坐标，
    所以两段命中各走各自的投影和深度。
  - 每个像素单独反射会带噪点，去噪按命中深度加权：深度相近的邻居才参与，
    避免把前后离得很远的物体糊在一起。
  - 默认关闭（`OMNI_SSR` 处于注释状态）：屏幕反射开销大，薄物体边缘还会有伪影，
    所以它做成可选增强，基础路径只保留天空反射。
*/

// 防止本文件被多处显式引用时重复声明这些函数。
#ifndef OMNI_REFLECTION
#define OMNI_REFLECTION
// 菜单：反射。默认关闭，先给基础画面一条不依赖屏幕内容的路。
// @effect {"label":{"zh_cn":"反射","en_us":"Reflections"}}
// 屏幕空间反射总开关，默认关闭（下一行被注释掉就是关闭）。
// @option {"label":{"zh_cn":"屏幕空间反射","en_us":"Screen-space reflections"}}
//#define OMNI_SSR
// 一次反射最多走多少步，步数多才不易漏掉远处几何，开销也越大。
// @option {"label":{"zh_cn":"反射步数","en_us":"Reflection steps"}}
#define OMNI_SSR_STEPS 24 // [12 24 48]
// 反射整体强度，零等于取消反射。
// @option {"label":{"zh_cn":"反射强度","en_us":"Reflection strength"},"slider":true}
#define OMNI_REFLECTION_STRENGTH 1.0 // [0.0 0.5 1.0]
// 开启后按命中深度加权邻点去噪，减少屏幕反射的噪点。
// @option {"label":{"zh_cn":"反射去噪","en_us":"Reflection denoise"},"description":{"zh_cn":"按命中深度相似度加权多点，减少屏幕反射噪点。","en_us":"Weights multiple taps by hit depth similarity to reduce SSR noise."}}
#define OMNI_REFLECTION_DENOISE 1 // [0 1]
// @option {"label":{"zh_cn":"反射模糊","en_us":"Reflection blur"},"description":{"zh_cn":"不去噪路径里十字模糊的半径；越大反射越糊。","en_us":"Cross-blur radius on the non-denoise path; larger blurs the reflection more."},"slider":true}
#define OMNI_REFLECTION_BLUR 1.0 // [0.0 0.5 1.0 2.0]
// 天空回退色由天空文件提供。
#include "/effects/sky.glsl"
// 屏幕外反射回退要与背景天空一致，所以复用云与氛围的合成，而不是只取纯天空色。
#include "/effects/cloud.glsl"
#include "/effects/atmosphere.glsl"
// 投影、逆投影和视空间还原都在这里，反射步进依赖它们。
#include "/common/coordinates.glsl"
// --- 反射去噪：按命中深度相似度加权邻点颜色 ---
// 为什么按深度加权：反射命中的是某个深度上的物体，只有落在同一层深度的邻居才是它的延续，
// 前后差很远的邻居属于别的物体，混进来会把反射糊成一片。粗糙表面用更大的足迹。
// 输入：`hitUv` 命中点的屏幕坐标，`hitDepth` 命中点的视空间深度，`roughness` 表面粗糙度。
vec3 omniReflectionFilter(vec2 hitUv, float hitDepth, float roughness) {
    float radius = mix(1.0,4.0,roughness); // 越粗糙的表面，去噪范围越大，对应越模糊的反射。
    vec2 pixel = radius/vec2(viewWidth,viewHeight); // 把像素半径折算成屏幕上的坐标步长。
    vec3 sum = texture(colortex3,hitUv).rgb; float weight = 1.0; // 中心样本权重固定为一，先放进平均。
    for (int i=0;i<8;i++) {
        float angle = float(i)*2.399963; // 黄金角旋转样本，避免规则条纹压在反射上。
        vec2 sampleUv = clamp(hitUv+vec2(cos(angle),sin(angle))*pixel,0.0,1.0); // 邻居坐标裁剪在屏幕内，越界采样会读到屏幕外的黑。
        float sampleDepth = texture(depthtex1,sampleUv).r; // 读邻居的不透明深度，用来判断它是否在同一层。
        if (sampleDepth>=0.999999) continue; // 邻居是天空，没有深度可比，不参与。
        vec3 sampleView = omniView(sampleUv,sampleDepth); // 把邻居还原成视空间位置。
        float similarity = exp(-abs(sampleView.z-hitDepth)*2.0); // 深度越接近权重越大，差得远则迅速趋零。
        sum += texture(colortex3,sampleUv).rgb*similarity; weight += similarity; // 按相似度累积颜色与权重。
    }
    return sum/max(weight,1e-4); // 用总权重归一化；权重下限防全被拒绝时除以零。
}
// --- 近景命中：用近景投影判断这一步是否撞上几何 ---
// 近景必须用普通投影：远景自己的投影和深度对不上近景几何，混用会把交点算到错误位置。
// 命中时写回屏幕坐标 `hitUv` 与视空间交点 `target`；用 `out` 是为了把两个结果一次带回。
bool omniNearHit(vec3 point, float stride, out vec2 hitUv, out vec3 target) {
    vec3 screen = omniProject(point); // 近景射线用普通投影得到屏幕坐标与深度。
    hitUv = screen.xy; target = vec3(0.0); // 先记下屏幕坐标，交点默认留空，调用方据此判断是否命中。
    if (any(lessThan(screen.xy,vec2(0.01))) || any(greaterThan(screen.xy,vec2(0.99)))) return false; // 落在屏幕外的样本没有可靠颜色，直接不命中。
    float depth = texture(depthtex1,screen.xy).r; // 只在自己的投影位置读近景深度，保证坐标与深度同源。
    if (depth>=0.999999) return false; // 该像素是天空，没有几何可反射。
    target = omniView(screen.xy,depth); // 命中处的真实视空间位置。
    float travel = -point.z+target.z; // 起点到命中面沿视方向的距离差。
    return travel>0.0 && travel<stride*1.5; // 差为正且不超过一步的一点五倍，才算这一步撞上而不是穿透。
}
// --- 远景命中：用远景投影判断这一步是否撞上几何 ---
// 只在近景没有几何时才接受，避免把近景几何冒用成远景反射，所以先查近景深度再查远景深度。
bool omniDistantHit(vec3 point, float stride, out vec2 hitUv, out vec3 target) {
#ifdef DISTANT_HORIZONS
    vec3 screen = omniProjectDistant(point); // 远景射线必须走远景投影，否则和远景深度对不上。
    hitUv = screen.xy; target = vec3(0.0); // 先记下屏幕坐标，交点默认留空。
    if (any(lessThan(screen.xy,vec2(0.01))) || any(greaterThan(screen.xy,vec2(0.99)))) return false; // 落在屏幕外不命中。
    if (texture(depthtex1,screen.xy).r<0.999999) return false; // 近景这里已有几何，远景不再越权接管。
    float depth = texture(dhDepthTex1,screen.xy).r; // 远景深度与远景投影成对读取，保证同源。
    if (depth>=0.999999) return false; // 远景也是天空，没有几何可反射。
    target = omniDistantView(screen.xy,depth); // 用远景逆投影还原真实位置。
    float travel = -point.z+target.z; // 与近景相同，比较沿视方向的距离差。
    return travel>0.0 && travel<stride*1.5; // 差为正且不超过一步的一点五倍才算命中。
#else
    hitUv = vec2(0.0); target = vec3(0.0); // 没有远景能力，明确把命中结果置空。
    return false; // 基础路径不做远景命中。
#endif
}
// --- 逐像素反射：步进命中几何后取屏幕颜色 ---
// 这是本文件的算法主干，整段从上往下读：算方向，定回退色，逐步试探，首次命中即停止。
vec3 omniReflected(vec3 view, vec3 normal, float roughness) {
    vec3 ray = reflect(omniNormalize(view),normal); // 在视空间求反射方向，省去把方向转回世界空间。
    vec3 skyDirection = mat3(gbufferModelViewInverse)*ray; // 反射方向转到世界空间，天空、云、氛围共用它。
    vec3 reflected = omniAtmosphere(omniCloud(omniSky(skyDirection),skyDirection,32000.0),skyDirection); // 回退色与背景天空同一套合成，屏幕外反射也能看到云与氛围。
#ifdef OMNI_SSR
    vec3 point = view + normal*0.15; // 起点沿法线抬起一点，避免刚出发就打到自己所在的表面。
    for (int i=0;i<OMNI_SSR_STEPS;i++) {
        float stride = 0.25 + float(i)*0.15; // 步长随步数增大：近处细走抓小物体，远处快走省步数。
        point += ray*stride; // 沿反射方向推进一步。
        if (point.z >= -near) break; // 推到了相机背后，屏幕不会再给样本，结束。
        vec2 hitUv; vec3 target; // 接收下面两个检测写回的命中坐标与交点。
        bool hit = omniNearHit(point,stride,hitUv,target); // 先按近景屏幕深度试。
        if (!hit) hit = omniDistantHit(point,stride,hitUv,target); // 近景没中，再按远景试。
        if (!hit || length(target-view)<=0.2) continue; // 没命中，或交点离起点太近（属于自身），都跳过继续走。
#if OMNI_REFLECTION_DENOISE == 1
        vec3 sampleColor = omniReflectionFilter(hitUv,target.z,roughness); // 开启去噪时按深度加权取命中颜色。
#else
        vec2 blur = vec2(roughness*roughness*0.025*OMNI_REFLECTION_BLUR); // 不去噪时用粗糙度决定一个小十字模糊范围，半径可调。
        vec3 sampleColor = texture(colortex3,hitUv).rgb * 0.4; // 命中颜色必须用与命中深度相同的屏幕坐标读取。
        sampleColor += texture(colortex3,clamp(hitUv+vec2(blur.x,0),0.0,1.0)).rgb*0.15; // 右侧相邻像素，权重相同。
        sampleColor += texture(colortex3,clamp(hitUv-vec2(blur.x,0),0.0,1.0)).rgb*0.15; // 左侧相邻像素，权重相同。
        sampleColor += texture(colortex3,clamp(hitUv+vec2(0,blur.y),0.0,1.0)).rgb*0.15; // 上方相邻像素，权重相同。
        sampleColor += texture(colortex3,clamp(hitUv-vec2(0,blur.y),0.0,1.0)).rgb*0.15; // 下方相邻像素，权重相同。
#endif
        float edge = smoothstep(0.01,0.12,min(min(hitUv.x,hitUv.y),min(1.0-hitUv.x,1.0-hitUv.y))); // 命中点越靠屏幕边缘权重越低，靠边时淡回天空回退。
        reflected = mix(reflected,sampleColor,edge); // 按边缘权重把屏幕颜色混进回退色，保留屏幕外的天空。
        break; // 第一个可用交点就够，结束步进。
    }
#endif
    return reflected; // 关闭屏幕反射时这里直接就是天空回退色。
}
// --- 反射入口：把底色和反射按菲涅耳混合 ---
// 输入：`color` 当前底色，`view` 相机指向表面的视空间矢量（从相机到表面，取负才指向相机），`normal` 视空间法线，
//       `materialParams` 材质（x 粗糙度、y 金属度），`uv` 屏幕坐标（当前未参与计算，保留给后续）。
vec3 omniReflection(vec3 color, vec3 view, vec3 normal, vec3 materialParams, vec2 uv) {
    if (OMNI_REFLECTION_STRENGTH<=0.0) return color; // 强度为零时提前返回，编译器会连同天空与屏幕采样一起移除。
    float metal = step(230.0/255.0,materialParams.y); // 材质标准高区间是金属标记，这里把它变成零或一。
    vec3 f0 = mix(vec3(materialParams.y),clamp(color,0.0,1.0),metal); // 金属用底色当反射色，非金属用标准里的反射率近似。
    float facing = max(dot(normal,omniNormalize(-view)),0.0); // 视线与法线的贴合度，掠射角时接近零。
    vec3 fresnel = f0 + (1.0-f0)*pow(1.0-facing,5.0); // 标准菲涅耳：正对反射弱，掠射反射强。
    fresnel *= (1.0-materialParams.x*0.8)*OMNI_REFLECTION_STRENGTH; // 越粗糙反射峰值越低，再乘用户强度。
    return color*(1.0-fresnel) + omniReflected(view,normal,materialParams.x)*fresnel; // 能量在底色与反射之间按比例分配。
}
#endif
