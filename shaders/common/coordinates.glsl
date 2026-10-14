// 坐标转换：在屏幕深度、视空间、世界空间与投影之间互换，并统一天空与远景判断。
// 调用位置：需要位置重建或屏幕判定的效果与绘制文件显式 #include "/common/coordinates.glsl"。
// 可复制示例：`vec3 view = omniSceneView(uv, false); vec3 world = omniWorld(view); bool sky = omniSkyPixel(uv);`
#ifndef OMNI_COORDINATES // 各效果共享一次坐标定义。
#define OMNI_COORDINATES // 防止多次显式引用重复声明。
// 共用加载器输入。
#include "/common/uniforms.glsl"
// 屏幕坐标与深度还原视空间米制位置，抗锯齿开启时先撤销本帧抖动。
vec3 omniView(vec2 uv, float depth) {
#if defined OMNI_ANTIALIASING && OMNI_AA_MODE == 2
    uv -= omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 深度重建撤销本帧几何抖动。
#endif
    vec4 clip = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0); // 齐次裁剪空间位置。
    return clip.xyz / clip.w; // 恢复视空间米制位置。
}
// 视空间位置转到相机相对世界位置。
vec3 omniWorld(vec3 view) { return (gbufferModelViewInverse * vec4(view, 1.0)).xyz; } // 相机相对世界位置。
// 视空间位置投影到屏幕，输出深度同样映射到零至一。
vec3 omniProject(vec3 view) {
    vec4 clip = gbufferProjection * vec4(view, 1.0); // 位置转换到齐次屏幕。
    vec3 screen = clip.xyz / clip.w * 0.5 + 0.5; // 深度同样映射到零至一。
#if defined OMNI_ANTIALIASING && OMNI_AA_MODE == 2
    screen.xy += omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 屏幕追踪与本帧几何对齐。
#endif
    return screen; // 共用投影约定。
}
// 视空间位置用远景自己的投影投到屏幕，没有远景时退回普通投影。
vec3 omniProjectDistant(vec3 view) {
#ifdef DISTANT_HORIZONS // 无远景时不引入独立投影。
    vec4 clip = dhProjection * vec4(view,1.0); // 远景射线必须使用远景自己的近远裁剪面。
    vec3 screen = clip.xyz / clip.w * 0.5 + 0.5; // 远景深度与屏幕位置保持同一投影。
#if defined OMNI_ANTIALIASING && OMNI_AA_MODE == 2
    screen.xy += omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 远景追踪恢复本帧抖动。
#endif
    return screen; // 远景专用屏幕坐标。
#else
    return omniProject(view); // 没有远景时不引入另一套坐标规则。
#endif
}
// 判断当前像素是否来自远景：近景深度空白而远景有几何。
bool omniDistantPixel(vec2 uv, bool opaqueDepth) {
#ifdef DISTANT_HORIZONS // 远景判断显式使用远景深度。
    float standardDepth = opaqueDepth ? texture(depthtex1,uv).r : texture(depthtex0,uv).r; // 近景深度先判断。
    float distantDepth = opaqueDepth ? texture(dhDepthTex1,uv).r : texture(dhDepthTex0,uv).r; // 远景深度只在近景空白时有效。
    return standardDepth >= 0.999999 && distantDepth < 0.999999; // 返回当前像素是否来自远景。
#else
    return false; // 基础路径没有远景像素。
#endif
}
// 用远景自己的逆投影还原视空间位置，没有远景时退回普通逆投影。
vec3 omniDistantView(vec2 uv, float depth) {
#ifdef DISTANT_HORIZONS // 重建远景时使用对应逆投影。
#if defined OMNI_ANTIALIASING && OMNI_AA_MODE == 2
    uv -= omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 与远景投影函数成对撤销当前抖动。
#endif
    vec4 clip = dhProjectionInverse * vec4(uv*2.0-1.0,depth*2.0-1.0,1.0); // 用远景逆投影还原位置。
    return clip.xyz/clip.w; // 返回与近景相同的视空间。
#else
    return omniView(uv,depth); // 离线基础路径使用普通逆投影。
#endif
}
// 重建场景的视空间位置：优先使用独立水深，否则按透明阶段选深度，远景再用自身投影。
vec3 omniSceneView(vec2 uv, bool opaqueDepth) {
    ivec2 pixel = clamp(ivec2(uv*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 元数据使用最近像素，避免边缘插值伪造水。
    vec4 waterMeta = texelFetch(colortex8,pixel,0); // 水深和有效性不能线性过滤。
    vec4 surfaceMeta = texelFetch(colortex7,pixel,0); // 类别与有效性和水深必须来自同一像素。
    if (!opaqueDepth && waterMeta.a<0.0 && surfaceMeta.a>=0.5) {
        vec2 positionUv = uv; // 水面重建使用对应抖动前的视线。
#if defined OMNI_ANTIALIASING && OMNI_AA_MODE == 2
        positionUv -= omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 撤销本帧水面抖动。
#endif
        vec4 ray = gbufferProjectionInverse*vec4(positionUv*2.0-1.0,0.0,1.0); // 近景水投影视线。
#ifdef DISTANT_HORIZONS
        if (surfaceMeta.z==2.0) ray = dhProjectionInverse*vec4(positionUv*2.0-1.0,0.0,1.0); // 远景水使用自身投影视线。
#endif
        return ray.xyz*(waterMeta.a/ray.z); // 按同片元记录的视深度得到真实位置。
    }
    float sceneDepth = opaqueDepth ? texture(depthtex1, uv).r : texture(depthtex0, uv).r; // 选取对应透明阶段。
#ifdef DISTANT_HORIZONS
    if (sceneDepth >= 0.999999) { // 近景深度空白才需要远景重建。
        float distantDepth = opaqueDepth ? texture(dhDepthTex1, uv).r : texture(dhDepthTex0, uv).r; // 标准深度空白才读取远景。
        if (distantDepth < 0.999999) {
            return omniDistantView(uv,distantDepth); // 远景必须用自己的投影。
        }
    }
#endif
    return omniView(uv, sceneDepth); // 基础加载器路径不依赖远景。
}
// 判断近景与远景共同的空白背景：两个深度都为空才是天空。
bool omniSkyPixel(vec2 uv) {
    ivec2 pixel = clamp(ivec2(uv*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 天空判定也使用最近元数据。
    if (texelFetch(colortex8,pixel,0).a<0.0 && texelFetch(colortex7,pixel,0).a>=0.5) return false; // 独立水深意味着有可见水表面。
    bool empty = texture(depthtex0, uv).r >= 0.999999; // 标准场景没有几何。
#ifdef DISTANT_HORIZONS
    empty = empty && texture(dhDepthTex0, uv).r >= 0.999999; // 远景也没有几何才是天空。
#endif
    return empty; // 提供统一背景判定。
}
#endif
