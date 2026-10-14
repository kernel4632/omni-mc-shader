// 坐标转换：所有深度使用对应投影，示例 omniView(uv, depth)。
#ifndef OMNI_COORDINATES // 各效果共享一次坐标定义。
#define OMNI_COORDINATES // 防止多次显式引用重复声明。
// 共用加载器输入。
#include "/common/uniforms.glsl"
vec3 omniView(vec2 uv, float depth) {
#if defined OMNI_ANTIALIASING && OMNI_AA_MODE == 2
    uv -= omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 深度重建撤销本帧几何抖动。
#endif
    vec4 p = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0); // 撤销标准投影。
    return p.xyz / p.w; // 恢复视空间米制位置。
}
vec3 omniWorld(vec3 view) { return (gbufferModelViewInverse * vec4(view, 1.0)).xyz; } // 相机相对世界位置。
vec3 omniProject(vec3 view) {
    vec4 p = gbufferProjection * vec4(view, 1.0); // 位置转换到齐次屏幕。
    vec3 screen = p.xyz / p.w * 0.5 + 0.5; // 深度同样映射到零至一。
#if defined OMNI_ANTIALIASING && OMNI_AA_MODE == 2
    screen.xy += omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 屏幕追踪与本帧几何对齐。
#endif
    return screen; // 共用投影约定。
}
vec3 omniProjectDistant(vec3 view) {
#ifdef DISTANT_HORIZONS // 无远景时不引入独立投影。
    vec4 p = dhProjection * vec4(view,1.0); // 远景射线必须使用远景自己的近远裁剪面。
    vec3 screen = p.xyz / p.w * 0.5 + 0.5; // 远景深度与屏幕位置保持同一投影。
#if defined OMNI_ANTIALIASING && OMNI_AA_MODE == 2
    screen.xy += omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 远景追踪恢复本帧抖动。
#endif
    return screen; // 远景专用屏幕坐标。
#else
    return omniProject(view); // 没有远景时不引入另一套坐标规则。
#endif
}
bool omniDistantPixel(vec2 uv, bool opaque) {
#ifdef DISTANT_HORIZONS // 远景判断显式使用远景深度。
    float nearDepth = opaque ? texture(depthtex1,uv).r : texture(depthtex0,uv).r; // 近景深度先判断。
    float distantDepth = opaque ? texture(dhDepthTex1,uv).r : texture(dhDepthTex0,uv).r; // 远景深度只在近景空白时有效。
    return nearDepth >= 0.999999 && distantDepth < 0.999999; // 返回当前像素是否来自远景。
#else
    return false; // 基础路径没有远景像素。
#endif
}
vec3 omniDistantView(vec2 uv, float depth) {
#ifdef DISTANT_HORIZONS // 重建远景时使用对应逆投影。
#if defined OMNI_ANTIALIASING && OMNI_AA_MODE == 2
    uv -= omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 与远景投影函数成对撤销当前抖动。
#endif
    vec4 p = dhProjectionInverse * vec4(uv*2.0-1.0,depth*2.0-1.0,1.0); // 用远景逆投影还原位置。
    return p.xyz/p.w; // 返回与近景相同的视空间。
#else
    return omniView(uv,depth); // 离线基础路径使用普通逆投影。
#endif
}
vec3 omniSceneView(vec2 uv, bool opaque) {
    ivec2 pixel = clamp(ivec2(uv*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 元数据使用最近像素，避免边缘插值伪造水。
    vec4 water = texelFetch(colortex8,pixel,0); // 水深和有效性不能线性过滤。
    vec4 surfaceMeta = texelFetch(colortex7,pixel,0); // 类别与有效性和水深必须来自同一像素。
    if (!opaque && water.a<0.0 && surfaceMeta.a>=0.5) {
        vec2 positionUv = uv; // 水面重建使用对应抖动前的视线。
#if defined OMNI_ANTIALIASING && OMNI_AA_MODE == 2
        positionUv -= omniJitter(frameCounter)/vec2(viewWidth,viewHeight); // 撤销本帧水面抖动。
#endif
        vec4 ray = gbufferProjectionInverse*vec4(positionUv*2.0-1.0,0.0,1.0); // 近景水投影视线。
#ifdef DISTANT_HORIZONS
        if (surfaceMeta.z==2.0) ray = dhProjectionInverse*vec4(positionUv*2.0-1.0,0.0,1.0); // 远景水使用自身投影视线。
#endif
        return ray.xyz*(water.a/ray.z); // 按同片元记录的视深度得到真实位置。
    }
    float d = opaque ? texture(depthtex1, uv).r : texture(depthtex0, uv).r; // 选取对应透明阶段。
#ifdef DISTANT_HORIZONS
    if (d >= 0.999999) { // 近景深度空白才需要远景重建。
        float h = opaque ? texture(dhDepthTex1, uv).r : texture(dhDepthTex0, uv).r; // 标准深度空白才读取远景。
        if (h < 0.999999) {
            return omniDistantView(uv,h); // 远景必须用自己的投影。
        }
    }
#endif
    return omniView(uv, d); // 基础加载器路径不依赖远景。
}
bool omniSkyPixel(vec2 uv) { // 判断近景与远景共同的空白背景。
    ivec2 pixel = clamp(ivec2(uv*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 天空判定也使用最近元数据。
    if (texelFetch(colortex8,pixel,0).a<0.0 && texelFetch(colortex7,pixel,0).a>=0.5) return false; // 独立水深意味着有可见水表面。
    bool empty = texture(depthtex0, uv).r >= 0.999999; // 标准场景没有几何。
#ifdef DISTANT_HORIZONS
    empty = empty && texture(dhDepthTex0, uv).r >= 0.999999; // 远景也没有几何才是天空。
#endif
    return empty; // 提供统一背景判定。
}
#endif
