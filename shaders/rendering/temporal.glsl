// 时间合成：当前颜色写零，历史写四和五；示例 composite1 引入。
#ifdef OMNI_VERTEX
out vec2 texcoord; // 全屏采样位置。
void main() { gl_Position = ftransform(); texcoord = gl_MultiTexCoord0.xy; } // 全屏时间合成。
#endif
#ifdef OMNI_FRAGMENT
// 时间与曝光读取同一历史有效性。
#include "/rendering/buffers.glsl"
#include "/effects/color.glsl"
in vec2 texcoord; // 当前像素。
/* RENDERTARGETS: 0,4,5 */
layout(location=0) out vec4 scene; // 最终线性场景。
layout(location=1) out vec4 history; // 下一帧颜色。
layout(location=2) out vec4 state; // 下一帧米制深度和曝光。
void main() {
    vec3 color = texture(colortex6,texcoord).rgb; // 当前合成输入。
    ivec2 pixel = clamp(ivec2(texcoord*vec2(viewWidth,viewHeight)),ivec2(0),ivec2(viewWidth-1.0,viewHeight-1.0)); // 颜色与元数据使用同一像素。
    bool overlay = texture(colortex6,texcoord).a<0.5 || texelFetch(colortex8,pixel,0).a<0.0; // 叠层与动态水同时拒绝读取和写入可复用的几何历史。
#if OMNI_AA_MODE == 1
    color = omniFxaa(texcoord); // 快速边缘平滑独立于历史。
#endif
    color = omniTaa(color,texcoord,state); // 关闭时间算法时只准备状态。
    state.g = omniExposure(texcoord); // 自动曝光与时间算法可独立启用。
    history = vec4(color,overlay?0.0:1.0); // 覆盖层不进入时间历史。
    scene = vec4(color,!overlay && omniHistoryValid()?1.0:0.0); // 翻转前的历史有效性显式传到最终镜头，避免检查本帧帧号。
    ivec2 metadataPixel = ivec2(gl_FragCoord.xy); // 元数据按像素定位，不依赖插值坐标。
    if (metadataPixel==ivec2(0,0)) state = vec4(viewWidth,viewHeight,omniDimension(),float(frameCounter)); // 尺寸与维度。
    if (metadataPixel==ivec2(1,0)) state = vec4(cameraPosition,float(frameCounter)); // 实际相机位置。
}
#endif
