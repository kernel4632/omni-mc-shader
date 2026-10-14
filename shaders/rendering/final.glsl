// 最终显示：镜头、泛光、曝光调色与调试，示例 final.fsh 引入。
#ifdef OMNI_VERTEX
out vec2 texcoord; // 全屏坐标。
void main() { gl_Position = ftransform(); texcoord = gl_MultiTexCoord0.xy; } // 最终四边形。
#endif
#ifdef OMNI_FRAGMENT
// 先声明抖动，再引用全部最终效果。
#include "/effects/color.glsl"
#include "/effects/bloom.glsl"
#include "/effects/lens.glsl"
#include "/effects/debug.glsl"
#include "/rendering/buffers.glsl"
in vec2 texcoord; // 当前屏幕位置。
layout(location=0) out vec4 color; // 显示颜色。
void main() {
    vec3 scene = texture(colortex0,texcoord).rgb; // 最后一次线性场景读取。
    scene = omniLens(scene,texcoord)+omniBloom(texcoord); // 镜头计算仍在线性空间。
    float exposure = texture(colortex5,vec2(0.5)).g; // 时间合成保存的真实曝光。
    scene = omniColor(scene,exposure); // 色调映射后只编码一次。
    color = vec4(debugColor(scene,texture(depthtex0,texcoord).r,texcoord),1.0); // 调试路径直接观察真实缓冲。
}
#endif
