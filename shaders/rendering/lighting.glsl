// 延迟快照：不透明阶段结束后保存照明，供透明折射与屏幕反射；示例 deferred 引入。
#ifdef OMNI_VERTEX
out vec2 texcoord; // 全屏纹理坐标。
void main() { gl_Position = ftransform(); texcoord = gl_MultiTexCoord0.xy; } // 加载器全屏四边形。
#endif
#ifdef OMNI_FRAGMENT // 在不透明阶段结束后保存快照。
// 缓冲约定与抗锯齿坐标。
#include "/rendering/buffers.glsl"
#include "/effects/antialiasing.glsl"
#include "/effects/cloud.glsl"
#include "/effects/atmosphere.glsl"
in vec2 texcoord; // 当前屏幕位置。
/* RENDERTARGETS: 0,3 */
layout(location=0) out vec4 scene; // 包含自定义天空的不透明颜色。
layout(location=1) out vec4 snapshot; // 透明阶段无法改写的不透明副本。
void main() {
    vec3 color = texture(colortex0,texcoord).rgb; // 保留不透明物体。
    if (omniSkyPixel(texcoord)) {
        vec3 direction = omniNormalize(mat3(gbufferModelViewInverse)*omniView(texcoord,1.0)); // 背景世界方向。
        color = omniAtmosphere(omniCloud(omniSky(direction),direction,32000.0),direction); // 先天空，再云与氛围。
    }
    scene = snapshot = vec4(color,1.0); // 快照在透明绘制前完成。
}
#endif
