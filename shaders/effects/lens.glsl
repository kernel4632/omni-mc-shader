// 镜头：把色差、景深、运动模糊、耀斑和暗角合成成一套相机成像效果，输入无效时保守回退为清晰原色。
// 调用位置：rendering/final.glsl 在线性颜色空间里调用 omniLens，把镜头效果叠到场景颜色上。
// 可复制示例：`scene = omniLens(scene, texcoord) + omniBloom(texcoord);`
// 设计取舍：这些效果共用一个文件，因为它们读同一套屏幕元数据、共享同一段屏幕坐标约定，拆成多个文件会让同一段取样逻辑散落多处；
//   但每个效果仍各自成一个函数，关闭某个效果时用预处理器在编译期直接去掉对应循环，不在运行时逐像素判断，避免为关闭的功能付出开销。
// 顺序原因：GLSL 不支持先调用后定义，所以入口 omniLens 放在文件末尾，上面的函数按被调用的先后排列。
#ifndef OMNI_LENS
#define OMNI_LENS
// @effect {"label":{"zh_cn":"镜头","en_us":"Lens"}}
// @option {"label": {"zh_cn": "景深开关", "en_us": "Depth of field"}, "description": {"zh_cn": "远处会不会模糊。", "en_us": "Whether distant things blur."}}
//#define OMNI_DOF
// @option {"label":{"zh_cn":"运动模糊开关","en_us":"Motion blur"},"description":{"zh_cn":"只有相机移动才模糊，手持物不模糊，也不包含生物自身速度。","en_us":"Camera motion only; excludes hands and has no entity velocity."}}
//#define OMNI_MOTION_BLUR
// @option {"label": {"zh_cn": "暗角强度", "en_us": "Vignette"}, "slider": true, "description": {"zh_cn": "画面四角变暗多少。", "en_us": "How much the corners darken."}}
#define OMNI_VIGNETTE 0.0 // [0.0 0.1 0.25 0.5]
// @option {"label": {"zh_cn": "色差强度", "en_us": "Chromatic aberration"}, "description": {"zh_cn": "画面边缘有没有彩边。", "en_us": "Colour fringing near the edges."}}
#define OMNI_CHROMATIC 0.0 // [0.0 0.5 1.0 2.0]
// @option {"label": {"zh_cn": "耀斑开关", "en_us": "Lens flare"}, "description": {"zh_cn": "从屏幕上的太阳亮部生成鬼影与光环，被挡住时自动减弱。", "en_us": "Draws ghosts and a halo from the on-screen sun highlight, fading when occluded."}, "values": {"0": {"zh_cn": "关", "en_us": "Off"}, "1": {"zh_cn": "开", "en_us": "On"}}}
#define OMNI_LENS_FLARE 1 // [0 1]
// @option {"label": {"zh_cn": "散景形状", "en_us": "Bokeh aperture"}, "description": {"zh_cn": "零为圆形散景，一为六边形光圈，使失焦高光成多边形。", "en_us": "Zero is a circular blur; one is a hexagonal aperture for polygonal highlights."}, "values": {"0": {"zh_cn": "圆形", "en_us": "Round"}, "1": {"zh_cn": "六边形", "en_us": "Hexagon"}}}
#define OMNI_BOKEH_SHAPE 1 // [0 1]
// @option {"label": {"zh_cn": "景深强度", "en_us": "Depth of field strength"}, "slider": true, "description": {"zh_cn": "模糊多强。", "en_us": "How strong the blur is."}}
#define OMNI_DOF_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label": {"zh_cn": "运动模糊强度", "en_us": "Motion blur strength"}, "slider": true, "description": {"zh_cn": "拖影多长。", "en_us": "How long the motion trail is."}}
#define OMNI_MOTION_BLUR_STRENGTH 1.0 // [0.0 0.5 1.0 1.5]
// @option {"label": {"zh_cn": "耀斑强度", "en_us": "Flare strength"}, "slider": true, "description": {"zh_cn": "光斑多亮。", "en_us": "How bright the lens flare is."}}
#define OMNI_FLARE_STRENGTH 1.0 // [0.0 0.5 1.0 1.5]
// 时间重投影、深度重建和镜头颜色来自统一的屏幕协议；这一行引入坐标、亮度等共用能力。
#include "/effects/antialiasing.glsl"

// --- 像素与颜色取样 ---

// 取一个镜头颜色样本：先取线性颜色，再让红蓝通道朝相反方向偏移，返回已经完成色差处理的颜色。
// 为什么色差先做：色差改变的是每个通道各自取样位置，后面的景深和运动模糊都基于这份错开的颜色做平均，顺序反了三种效果会互相打架。
vec3 omniLensSample(vec2 uv) {
    vec3 color = texture(colortex0,uv).rgb; // 取当前样本的线性颜色，后续效果在线性空间里平均不会偏色。
    if (OMNI_CHROMATIC<=0.0) return color; // 关闭色差时直接返回，省下两次额外纹理读取。
    vec2 offset = (uv-0.5)*OMNI_CHROMATIC/vec2(viewWidth,viewHeight); // 偏移随到画面中心的距离变大，画面边缘色差更明显，符合真实镜头。
    color.r = texture(colortex0,clamp(uv+offset,0.0,1.0)).r; // 红色通道向外偏移；取样点可能超出画面，先夹紧到合法范围。
    color.b = texture(colortex0,clamp(uv-offset,0.0,1.0)).b; // 蓝色通道向内偏移，与红色方向相反以形成完整色散。
    return color; // 返回已经完成色差的线性颜色。
}

// --- 光圈与景深 ---

// 光圈形状：给定采样方向的角度，返回该方向上多边形光圈的边界半径相对内切圆的比例。
// 为什么需要它：真实镜头由若干片叶片组成光圈，失焦的高光会变成多边形而不是圆；这里用叶片数描述边界，让散景呈现六边形。
// 考虑点：返回值是相对比例，一表示不考虑形状；取样时乘以弥散半径就得到多边形散景，不必改动景深本身的算法。
float omniApertureRadius(float angle) {
#if OMNI_BOKEH_SHAPE == 0
    return 1.0; // 圆形光圈：每个方向边界半径相同，直接返回一。
#else
    const float blades = 6.0; // 六片光圈叶片，决定多边形有几条边。
    float sector = 6.2831853/blades; // 每片叶片覆盖的角度，一整圈除以叶片数。
    float local = abs(mod(angle,sector)-sector*0.5); // 当前方向离最近边中点的角度差，用来求这条边的边界。
    return cos(sector*0.5)/cos(local); // 内切圆半径除以方向上的余弦，得到多边形边界半径的比例。
#endif
}
// 读取一个景深样本：先取颜色并拒绝无法判定深度的像素，再对有效方向做散焦平均。
// 为什么先拒绝手和叠层：手和覆盖层没有单一的表面深度，若参与散焦会把清晰的手或界面糊掉，所以只对普通表面做景深。
vec3 omniFocusSample(vec2 uv) {
    ivec2 pixel = omniPixel(uv); // 先算出整数像素编号，后面几处类别读取都复用它。
    vec4 geometry = texelFetch(colortex1,pixel,0); // 精确读取手的类别，类别是离散标记，线性插值会混出不存在的值。
    vec4 surface = texelFetch(colortex7,pixel,0); // 精确读取几何有效标记，同理不能插值。
    vec3 color = omniLensSample(uv); // 先完成色差，保证景深在色差之后处理。
    if (surface.a<0.5 || geometry.a==2.0) return color; // 覆盖层或手没有单一表面深度，直接返回清晰颜色，不做景深。
#ifndef OMNI_DOF
    return color; // 关闭景深时不读取深度、也不进入采样循环，省掉全部散焦开销。
#else
    ivec2 centerPixel = ivec2(viewWidth*0.5,viewHeight*0.5); // 自动对焦固定在屏幕中心，符合第一人称取景把注意力放在中间的直觉。
    vec4 centerGeometry = texelFetch(colortex1,centerPixel,0); // 精确读取中心像素的类别，用来判断中心是不是手。
    float focus = length(omniSceneView(vec2(0.5),false)); // 默认用中心普通表面的视空间距离作为焦平面。
    if (centerGeometry.a==2.0) focus = length(omniView(vec2(0.5),texture(depthtex2,vec2(0.5)).r)); // 中心被手挡住时改用不透明深度，避免把手当成对焦点。
    float distance = length(omniSceneView(uv,false)); // 当前像素表面的真实视空间距离，作为弥散量的依据。
    float radius = min(abs(distance-focus)/max(distance,0.1)*8.0*OMNI_DOF_STRENGTH,8.0); // 越远离焦平面弥散越大；强度选项整体放大或缩小，上限八像素防止性能失控。
    if (isnan(radius)) return color; // 深度重建异常时保留清晰原色，不让坏值糊成黑块。
    vec3 sum = color; float weight = 1.0; // 当前像素先计入平均，保证至少有一个有效样本。
    for (int i=0;i<8;i++) {
        float angle = float(i)*2.399963; // 黄金角螺旋分布，八个样本在圆盘上铺得均匀，比规则网格更少出现条纹。
        float shaped = radius*omniApertureRadius(angle); // 用光圈形状调制这个方向的取样半径，得到多边形散景。
        vec2 sampleUv = clamp(uv+vec2(cos(angle),sin(angle))*shaped/vec2(viewWidth,viewHeight),0.0,1.0); // 把像素半径换算成屏幕坐标并夹紧在画面内。
        ivec2 samplePixel = omniPixel(sampleUv); // 样本的类别同样用整数像素精确读取。
        if (texelFetch(colortex1,samplePixel,0).a==2.0 || texelFetch(colortex7,samplePixel,0).a<0.5 || length(omniSceneView(sampleUv,false))<distance*0.75) continue; // 手、覆盖层和明显更近的前景都跳过，避免远处背景糊到近处物体上形成光晕。
        sum += omniLensSample(sampleUv); weight += 1.0; // 有效样本按色差后的颜色累加并计数。
    }
    return sum/weight; // 只对有效样本求平均，样本少时亮度也不会被拉低。
#endif
}

// --- 运动模糊 ---

// 相机运动模糊：用上一帧相机把当前表面重投影回屏幕，沿两帧之间的屏幕位移方向取几个历史位置做平均，模拟快门时间内相机的移动。
// 为什么只做相机运动：实体自身速度没有输入缓冲，硬用会把静止物体也拖出鬼影，所以这里只处理相机移动造成的整屏位移。
// 考虑点：所有无效情况都提前返回，循环里只处理确实可追踪的有效快门样本。
vec3 omniMotionBlur(vec3 color, vec2 uv) {
#ifndef OMNI_MOTION_BLUR
    return color; // 关闭运动模糊时没有深度、历史或矩阵读取，直接返回原色。
#else
    ivec2 pixel = omniPixel(uv); // 当前像素的整数编号，用于精确读取元数据。
    if (texelFetch(colortex1,pixel,0).a==2.0 || texelFetch(colortex7,pixel,0).a<0.5 || texelFetch(colortex0,pixel,0).a<0.5) return color; // 手、覆盖层和颜色无效的像素保持清晰，它们没有可追踪的历史。
    if (omniSkyPixel(uv)) return color; // 天空没有可追踪的表面，重投影没有意义。
    if (length(cameraPosition-previousCameraPosition)>=8.0) return color; // 一帧跨过八米说明发生了传送或重载，上一帧历史已不属于同一场景。
    vec3 currentView = omniSceneView(uv,false); // 用当前深度还原表面的视空间位置。
    vec3 absoluteWorld = omniWorld(currentView)+cameraPosition; // 加上相机位置得到绝对世界坐标，跨帧才不会随相机一起漂移。
    vec3 previousView = (gbufferPreviousModelView*vec4(absoluteWorld-previousCameraPosition,1.0)).xyz; // 用上一帧相机把它转回上一帧的视空间。
    vec4 projected = gbufferPreviousProjection*vec4(previousView,1.0); // 普通表面投影到上一帧的屏幕位置。
#ifdef DISTANT_HORIZONS
    if (omniDistantPixel(uv,false)) projected = dhPreviousProjection*vec4(previousView,1.0); // 远景表面必须用远景自己的历史投影，否则位置会错。
#endif
    if (projected.w<=0.0 || any(isnan(projected))) return color; // 先检查齐次分量再相除，避免相机后方或非有限值算出错误坐标。
    vec2 previousUnjittered = projected.xy/projected.w*0.5+0.5; // 得到未抖动的上一帧屏幕坐标，作为去抖动后的基准。
    vec2 previousUv = previousUnjittered; // 默认直接用这个基准，未开启抗锯齿时没有抖动要恢复。
    vec2 currentUnjittered = uv; // 当前坐标默认保持原位置。
#if defined OMNI_ANTIALIASING && defined OMNI_AA_ENABLED
    previousUv = previousUnjittered+omniJitter(frameCounter-1)/vec2(viewWidth,viewHeight); // 只有时间抗锯齿开着时，历史坐标才要补回上一帧的抖动。
    currentUnjittered -= omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 当前坐标先撤掉本帧抖动，两帧才对齐在同一基准上。
#endif
    if (any(lessThan(previousUv,vec2(0))) || any(greaterThan(previousUv,vec2(1)))) return color; // 上一帧坐标跑到屏幕外说明表面刚进入视野，没有历史可平均。
    vec2 velocity = clamp((currentUnjittered-previousUnjittered)*OMNI_MOTION_BLUR_STRENGTH,vec2(-0.05),vec2(0.05)); // 用去抖动后的两帧坐标算屏幕位移，抖动不会混进速度；强度选项整体放大或缩小。
    vec3 sum = color; float weight = 1.0; // 当前像素先进入快门平均。
    for (int i=1;i<6;i++) {
        vec2 sampleUv = clamp(uv-velocity*float(i)/6.0,0.0,1.0); // 沿相机轨迹往回取样，越早的快门时刻偏移越大。
        ivec2 samplePixel = omniPixel(sampleUv); // 采样点的类别同样精确读取。
        if (texelFetch(colortex1,samplePixel,0).a==2.0 || texelFetch(colortex7,samplePixel,0).a<0.5) continue; // 手和覆盖层不进入快门，否则静止的手也会被拖模糊。
        sum += omniFocusSample(sampleUv); weight += 1.0; // 每个样本走完整的色差加景深流程，保证整体效果顺序一致。
    }
    return sum/weight; // 按实际有效样本归一化，样本少时画面不会变暗。
#endif
}

// --- 耀斑 ---

// 求屏幕上的太阳位置：把加载器给的视空间太阳方向投影到屏幕，太阳在相机后方或超出画面时返回假。
// 用输出参数带回屏幕坐标，返回假就表示不该画耀斑。
bool omniSunScreen(out vec2 sunUv) {
    vec3 sunView = omniNormalize(sunPosition); // 归一化视空间太阳方向，长度不影响投影结果。
    if (sunView.z>=0.0) return false; // 视空间里朝向相机后方的太阳不会出现在画面里，直接放弃。
    vec4 clip = gbufferProjection*vec4(sunView,0.0); // 方向向量用投影矩阵的线性部分投影到裁剪空间。
    if (clip.w<=0.0) return false; // 齐次分量非正时相除会翻转符号，先拒绝。
    sunUv = clip.xy/clip.w*0.5+0.5; // 归一化到零到一的屏幕坐标。
    return all(greaterThanEqual(sunUv,vec2(0))) && all(lessThanEqual(sunUv,vec2(1))); // 只有太阳落在画面内才返回真。
}
// 镜头耀斑：从屏幕上太阳的亮部生成一串鬼影和一个光环，被云或地形遮挡以及夜里时自动减弱。
// 为什么取现有画面的亮部当光源：不新增附件；遮挡太阳的物体会让亮部变暗，耀斑就自然跟着减弱，无需额外的可见性判断。
vec3 omniLensFlare(vec2 uv) {
#if OMNI_LENS_FLARE == 0
    return vec3(0.0); // 关闭耀斑时不读太阳位置，也不做任何额外采样。
#else
    vec2 sunUv; // 屏幕上的太阳坐标。
    if (!omniSunScreen(sunUv)) return vec3(0.0); // 太阳不在画面内就没有耀斑。
    float source = max(omniLuminance(texture(colortex0,sunUv).rgb)-1.0,0.0); // 只有超过一的高光亮部才算光源，普通亮度不产生耀斑。
    vec2 aspect = vec2(viewWidth/viewHeight,1.0); // 用屏幕宽高比修正距离，让鬼影和光环是圆而不是被拉长的椭圆。
    vec2 axis = sunUv-0.5; // 屏幕中心到太阳的方向，鬼影沿它反向排布。
    vec3 flare = vec3(0.0); // 累加所有鬼影与光环。
    for (int i=1;i<=4;i++) {
        vec2 ghostUv = 0.5-axis*float(i)*0.6; // 鬼影穿过屏幕中心排列在太阳的对称侧，越远的一枚离太阳越远。
        float distance = length((uv-ghostUv)*aspect); // 到鬼影中心、按宽高比修正后的距离。
        flare += exp(-distance*distance*80.0)*vec3(0.6,0.75,1.0)/float(i+1); // 高斯亮点，偏冷色，序号越大越暗。
    }
    float halo = exp(-pow(length((uv-sunUv)*aspect),2.0)*6.0); // 太阳近旁的柔和光环。
    flare += halo*vec3(1.0,0.86,0.62); // 光环用暖色，模拟主角耀光。
    float daylight = smoothstep(-0.15,0.1,dot(omniNormalize(sunPosition),omniNormalize(upPosition))); // 用太阳相对地平线的高度控制白天强度，夜里不出现耀斑。
    return flare*source*daylight*OMNI_FLARE_STRENGTH; // 亮部强度、遮挡程度、白昼程度与强度选项相乘，决定最终耀斑。
#endif
}

// --- 最终镜头顺序 ---

// 最终镜头顺序：色差与景深、运动模糊、耀斑、暗角依次叠加，返回这一帧的镜头颜色。
// 顺序原因：色差和景深先作用在原始颜色上，运动模糊取样时再走同一条流程；耀斑是加光，必须放在暗角之前，否则会被暗角连带压暗。
// 调用位置：rendering/final.glsl。
vec3 omniLens(vec3 color, vec2 uv) {
#if defined OMNI_DOF || defined OMNI_MOTION_BLUR
    color = omniFocusSample(uv); // 只要开了景深或运动模糊，就用统一入口拿到带色差、可散焦的颜色。
#else
    if (OMNI_CHROMATIC>0.0) color = omniLensSample(uv); // 两者都关时只按需做色差，跳过整套散焦循环。
#endif
    color = omniMotionBlur(color,uv); // 运动模糊内部自行处理关闭状态和各种提前返回。
    color += omniLensFlare(uv); // 镜头耀斑在暗角之前叠加。
    return color*(1.0-OMNI_VIGNETTE*smoothstep(0.1,0.7,length(uv-0.5))); // 暗角最后应用，离画面中心越远压得越暗。
}
#endif
