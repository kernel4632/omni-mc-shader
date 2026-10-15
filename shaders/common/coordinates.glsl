// 坐标：在屏幕深度、视空间、相机相对世界位置和投影之间互相换算，并统一判断远景与天空。
// 调用位置：effects/ambient.glsl、effects/shadow.glsl、effects/reflection.glsl 与 effects/antialiasing.glsl 引入本文件。
// 可复制示例：`vec3 view = omniSceneView(uv,false); vec3 world = omniWorld(view); bool sky = omniSkyPixel(uv);`
// 关键设计原因与取舍：投影和反投影必须成对使用同一套矩阵，而远景自带另一套近远裁剪面，
// 所以远近两套各写成一对函数，由调用者按像素来源选择，不用一套矩阵硬套两种裁剪面。
// 深度和类别这类离散标记一律按最近像素读取：线性过滤会把两种标记插值成一个不存在的中间值，伪造成不存在的几何或水面。
// 组织方式：先写各处复用的工具函数，再写对外函数，保证每个函数用到的都在它前面定义，读的时候由工具读到组合。
#ifndef OMNI_COORDINATES // 各效果共享一次坐标定义。
#define OMNI_COORDINATES // 防止多次显式引用重复声明。
// 共用加载器输入。
#include "/common/uniforms.glsl"

// --- 本帧抖动换算到屏幕坐标的偏移量 ---
// 顶点投影时加上、坐标重建时减去，读历史和写历史才能落在同一套像素上精确对齐。
// 把这段换算收在一处，调用方不必再写条件判断，也不会出现某一处忘记开关的漏洞。
vec2 omniJitterOffset() {
#if defined OMNI_ANTIALIASING && defined OMNI_AA_ENABLED
    return omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 抖动量以像素为单位，除以分辨率换算成零至一的屏幕偏移。
#else
    return vec2(0.0); // 没有时间抗锯齿就没有抖动，返回零让减法与加法都退化成恒等操作。
#endif
}

// --- 取屏幕坐标对应的最近像素坐标 ---
// 水深度、类别这类离散标记不能线性过滤，只能整块读取，否则会读出一个不存在的中间值。
// 为什么还要夹取范围：坐标可能带插值误差，画面边缘会落到最后一行之外，夹取后就不会越界读取。
ivec2 omniPixel(vec2 uv) {
    return clamp(ivec2(uv*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 上限取到最后一列与最后一行。
}

// --- 判断某个像素是否记录了可见水面 ---
// 水面是透明几何，普通深度缓冲记不到它，只能用独立通道里的水深度和表面类别共同确认。
// 为什么两项都要看：只看水深度会在没写水面的像素上误判，只看类别又会把不透明表面当成水。
bool omniWaterSurface(ivec2 pixel) {
    float waterDepth = texelFetch(colortex8,pixel,0).a; // colortex8 保存水面的视空间深度，负值表示这里确实有水面。
    float surfaceValid = texelFetch(colortex7,pixel,0).a; // colortex7 保存表面类别是否有效，用来确认同一像素输出了水面。
    return waterDepth<0.0 && surfaceValid>=0.5; // 两个标记同时成立才认定是可见水面。
}

// --- 屏幕坐标与深度还原视空间米制位置 ---
// 深度的非线性由投影矩阵的逆统一处理，本函数不区分远近，只负责一套裁剪面。
// 时间抗锯齿开启时先撤销本帧抖动，读回的才是几何真正的像素，而不是抖动过的像素。
vec3 omniView(vec2 uv, float depth) {
    uv -= omniJitterOffset(); // 撤销本帧抖动，未开启抗锯齿时偏移是零，这一步等于没做。
    vec4 clip = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0); // 还原到齐次裁剪空间位置。
    return clip.xyz / clip.w; // 除以齐次分量得到视空间米制位置。
}

// --- 视空间位置转到相机相对世界位置 ---
// 乘相机矩阵的逆，得到还没加上相机绝对偏移的世界坐标，多个效果要用同一个世界原点。
vec3 omniWorld(vec3 view) {
    return (gbufferModelViewInverse * vec4(view, 1.0)).xyz; // 只取位置分量，忽略第四分量的影响。
}

// --- 视空间位置投影到屏幕 ---
// 输出坐标和深度都映射到零至一，和深度纹理的约定保持一致，深层才能直接用。
// 时间抗锯齿开启时补上本帧抖动，屏幕追踪得到的位置才能和抖动后的几何对齐。
vec3 omniProject(vec3 view) {
    vec4 clip = gbufferProjection * vec4(view, 1.0); // 近景投影得到齐次屏幕坐标。
    vec3 screen = clip.xyz / clip.w * 0.5 + 0.5; // 齐次除法后从负一到一映射到零至一。
    screen.xy += omniJitterOffset(); // 补上本帧抖动，未开启抗锯齿时偏移是零。
    return screen; // 返回共用投影约定下的屏幕坐标。
}

// --- 视空间位置用远景自己的投影投到屏幕 ---
// 远景裁剪面与近景不同，必须使用配套矩阵，否则屏幕位置和深度都对不上。
// 没有远景加载器时退回普通投影，只保留一条可用路径，不引入第二套坐标规则。
vec3 omniProjectDistant(vec3 view) {
#ifdef DISTANT_HORIZONS
    vec4 clip = dhProjection * vec4(view,1.0); // 远景位置必须使用远景自己的近远裁剪面。
    vec3 screen = clip.xyz / clip.w * 0.5 + 0.5; // 远景深度与屏幕位置保持同一投影。
    screen.xy += omniJitterOffset(); // 补上本帧抖动，和远景顶点阶段的抖动成对。
    return screen; // 返回远景专用屏幕坐标。
#else
    return omniProject(view); // 没有远景时不引入另一套坐标规则。
#endif
}

// --- 用远景自己的逆投影还原视空间位置 ---
// 远景用独立裁剪面，必须配套自己的逆矩阵，才能得到和近景同一尺度的米制位置。
// 没有远景加载器时退回普通逆投影，屏幕判定的调用方不用改。
vec3 omniDistantView(vec2 uv, float depth) {
#ifdef DISTANT_HORIZONS
    uv -= omniJitterOffset(); // 和远景投影函数成对撤销当前抖动。
    vec4 clip = dhProjectionInverse * vec4(uv*2.0-1.0,depth*2.0-1.0,1.0); // 用远景逆投影还原位置。
    return clip.xyz/clip.w; // 返回与近景相同的视空间单位。
#else
    return omniView(uv,depth); // 离线基础路径使用普通逆投影。
#endif
}

// --- 判断当前像素是否来自远景 ---
// 近景深度空白、远景深度有几何，两者同时成立才算远景像素。
// 为什么要先看近景：近景有几何时远景深度没有意义，不能仅凭它判断像素来源。
bool omniDistantPixel(vec2 uv, bool opaqueDepth) {
#ifdef DISTANT_HORIZONS // 没有远景加载器时下面的判断没有意义。
    float standardDepth = opaqueDepth ? texture(depthtex1, uv).r : texture(depthtex0, uv).r; // 先读近景深度。
    float distantDepth = opaqueDepth ? texture(dhDepthTex1, uv).r : texture(dhDepthTex0, uv).r; // 远景深度只在近景空白时有效。
    return standardDepth >= 0.999999 && distantDepth < 0.999999; // 近景空且远景有几何才是远景像素。
#else
    return false; // 基础路径没有远景像素。
#endif
}

// --- 重建可见水面的视空间位置 ---
// 依次还原抖动、用近景或远景逆投影求出该像素的视线，最后按记录的视深度缩放到真实位置。
// 为什么单独重建：水面在普通深度里是一片空白，直接按深度重建只会得到远处背景或天空。
vec3 omniWaterView(vec2 uv, ivec2 pixel) {
    vec2 positionUv = uv; // 以当前像素作为视线基准。
    positionUv -= omniJitterOffset(); // 撤销本帧水面抖动，和投影时加抖动成对。
    vec4 ray = gbufferProjectionInverse*vec4(positionUv*2.0-1.0,0.0,1.0); // 近景逆投影得到该像素的视线方向。
#ifdef DISTANT_HORIZONS
    if (texelFetch(colortex7,pixel,0).z==2.0) ray = dhProjectionInverse*vec4(positionUv*2.0-1.0,0.0,1.0); // 远景水改用远景逆投影，近景矩阵对远景无效。
#endif
    float waterDepth = texelFetch(colortex8,pixel,0).a; // 读取同一像素记录的视深度。
    return ray.xyz*(waterDepth/ray.z); // 沿视线把单位方向缩放到真实米制位置。
}

// --- 按深度重建其它像素的视空间位置 ---
// 近景有几何就用近景，近景空白时才看远景，两段各用配套的逆投影。
// 为什么近景优先：远景只补近景空白处，近景有几何时远景深度没有意义，不能参与重建。
vec3 omniSceneFromDepth(vec2 uv, float sceneDepth, bool opaqueDepth) {
#ifdef DISTANT_HORIZONS
    if (sceneDepth < 0.999999) return omniView(uv, sceneDepth); // 近景有几何时直接重建，不必再读远景。
    float distantDepth = opaqueDepth ? texture(dhDepthTex1, uv).r : texture(dhDepthTex0, uv).r; // 近景空白才读对应阶段的远景深度。
    if (distantDepth < 0.999999) return omniDistantView(uv,distantDepth); // 远景有几何就用远景自己的逆投影重建。
#endif
    return omniView(uv, sceneDepth); // 其余情况用近景深度重建，没有远景加载器时也走这里。
}

// --- 重建场景在某个像素的视空间位置 ---
// 顺序是水面、近景、远景；水面在普通深度里是空白，必须最先单独处理，否则会被误当成天空背景。
// 元数据是离散标记，必须和类别一起按最近像素整块读取，边缘才不会插值出不存在的水面。
vec3 omniSceneView(vec2 uv, bool opaqueDepth) {
    ivec2 pixel = omniPixel(uv); // 先统一取最近像素。
    if (!opaqueDepth && omniWaterSurface(pixel)) return omniWaterView(uv,pixel); // 透明阶段遇到可见水面，用同片元记录的深度重建。
    float sceneDepth = opaqueDepth ? texture(depthtex1, uv).r : texture(depthtex0, uv).r; // 其余像素按透明阶段选对应深度。
    return omniSceneFromDepth(uv, sceneDepth, opaqueDepth); // 余下按近景优先、远景补充的选择重建。
}

// --- 判断像素是不是天空背景 ---
// 近景和远景都没有几何，也没有可见水面，才算天空。
// 为什么先看水面：透明水的深度记在独立通道里，普通深度缓冲看到的是一片空白，容易误判成天空。
bool omniSkyPixel(vec2 uv) {
    if (omniWaterSurface(omniPixel(uv))) return false; // 有可见水面就不是天空。
    bool empty = texture(depthtex0, uv).r >= 0.999999; // 近景没有几何。
#ifdef DISTANT_HORIZONS
    empty = empty && texture(dhDepthTex0, uv).r >= 0.999999; // 远景也没有几何。
#endif
    return empty; // 两个深度都空白才是天空。
}
#endif
