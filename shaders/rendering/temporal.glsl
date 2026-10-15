/*
时间合成：把抗锯齿之后的线性颜色整理成三样东西——最终场景颜色、下一帧颜色历史、下一帧元数据。
它是「合成」之后、「最终显示」之前的绘制主体，由三个维度的 `composite1.fsh` 入口显式引入。

调用位置：
  三个维度的入口文件只声明阶段与片段宏，真正的绘制全部交给本文件：
    #define OMNI_FRAGMENT
    #include "/rendering/temporal.glsl"
  内部按顺序复用两个效果文件：
    effects/antialiasing.glsl  提供快速边缘平滑 omniFxaa 与时间合成 omniTaa；
    effects/color.glsl         提供自动曝光 omniExposure。
  抗锯齿模式等由抗锯齿自己的选项决定，本文件不重复定义选项。

可复制示例：
  入口侧（粘贴进 `composite1.fsh` 即可）：
    #define OMNI_FRAGMENT
    #include "/rendering/temporal.glsl"
  本文件没有对外函数，全部逻辑只服务这一条绘制流程。

本文件直接读写的中间画面（编号约定见 rendering/buffers.glsl）：
  colortex6  合成阶段准备好的线性颜色；透明通道小于半表示这里是叠层。
  colortex8  水面编码法线与实际视深度；透明通道为负表示该像素退出几何历史。
  colortex0  写入最终线性场景颜色；透明通道写翻转前的历史有效性，供最终显示读取。
  colortex4  写入下一帧颜色历史；透明通道标记该像素是否参与历史。
  colortex5  写入下一帧元数据；左下角放尺寸与维度，第二像素放相机位置。

关键设计原因与取舍：
  历史有效性在「翻转」之前就写进 colortex0 的透明通道。翻转指的是历史缓冲在后续阶段已经交换成旧帧，
  等最终显示再判断时，读到的帧号状态已经不属于当前帧。所以这里提前把结论算好，最终显示只读一个标记。
  元数据用整数像素坐标定位，而不是插值出来的坐标。原因：帧号、尺寸、维度都是离散量，插值会把两个
  相邻像素混成一个本不存在的值，固定像素必须精确落位，所以用 `ivec2(gl_FragCoord.xy)`。
  叠层和退出历史的水面一律不复用几何历史：它们没有可靠的底层深度，沿用旧历史会拖出错误画面。
  代价是这类像素始终使用当前帧颜色，时间抗锯齿在它们身上不生效，换来的是历史不被污染。
*/
#ifdef OMNI_VERTEX
out vec2 texcoord; // 全屏四边形的纹理坐标。
void main() { gl_Position = ftransform(); texcoord = gl_MultiTexCoord0.xy; } // 全屏覆盖整张画面，坐标直接取自固定顶点。
#endif
#ifdef OMNI_FRAGMENT
// 复用中间画面编号约定，下面写入零号、四号、五号画面。
#include "/rendering/buffers.glsl"
// 颜色效果提供自动曝光函数，与时间算法各自独立。
#include "/effects/color.glsl"
in vec2 texcoord; // 当前片元对应的屏幕坐标，由顶点阶段插值得到。
/* RENDERTARGETS: 0,4,5 */
layout(location=0) out vec4 scene; // 零号画面：最终线性场景颜色。
layout(location=1) out vec4 history; // 四号画面：下一帧颜色历史。
layout(location=2) out vec4 state; // 五号画面：下一帧元数据。

// --- 判断一个像素是否不能复用几何历史 ---
// 叠层就是叠加在画面上的半透明覆盖（雨、粒子、手持物等），它们没有可靠的底层深度；
// 退出历史的水面是已经离开几何时间积累的透明水面。两种情况都不能沿用旧的几何历史，否则会拖影或错位。
// 为什么合并成一个判断：下面读取和写入历史必须给出同一个结论，写在一起才不会一边写入一边漏读。
bool omniRejectsHistory(vec2 uv, ivec2 pixel) {
    return texture(colortex6,uv).a<0.5 || texelFetch(colortex8,pixel,0).a<0.0; // 叠层透明通道过小，或水面标记为退出历史。
}

// --- 在帧内固定像素写入下一帧要用的元数据 ---
// 帧号、尺寸、维度和相机位置都要跨帧比对，必须精确落在一个确定像素上，不能使用插值坐标。
// 为什么放在最后执行：前面算好的曝光只服务普通像素，元数据像素会被整体覆盖，顺序颠倒就会写错。
void omniWriteMetadata() {
    ivec2 metadataPixel = ivec2(gl_FragCoord.xy); // 用整数像素坐标，避开插值带来的相邻像素混合。
    if (metadataPixel==ivec2(0,0)) state = vec4(viewWidth,viewHeight,omniDimension(),float(frameCounter)); // 左下角保存画面尺寸与当前维度。
    if (metadataPixel==ivec2(1,0)) state = vec4(cameraPosition,float(frameCounter)); // 第二像素保存真实相机位置，供下一帧判断是否传送。
}

// --- 时间合成主流程：颜色、历史、元数据各写各的画面 ---
void main() {
    vec3 color = texture(colortex6,texcoord).rgb; // 合成阶段准备好的线性颜色，作为时间合成的输入。
    ivec2 pixel = omniPixel(texcoord); // 与颜色采样同一像素的整数坐标，供精确读取水面标记。
    bool overlay = omniRejectsHistory(texcoord,pixel); // 这个像素是否不能复用几何历史。
#if OMNI_AA_MODE == 1
    color = omniFxaa(texcoord); // 快速边缘平滑不读取历史，独立于时间算法。
#endif
    color = omniTaa(color,texcoord,state); // 时间合成；关闭时间算法时只准备元数据，颜色保持当前帧。
    state.g = omniExposure(texcoord); // 曝光单独计算，自动曝光与时间算法可以各自开关。
    history = vec4(color,overlay?0.0:1.0); // 写下一帧颜色历史；叠层写零标记，表示不参与复用。
    scene = vec4(color,!overlay && omniHistoryValid()?1.0:0.0); // 在翻转前把历史有效性写进最终颜色的透明通道。
    omniWriteMetadata(); // 最后覆盖固定像素，保证元数据不被上面的曝光覆盖。
}
#endif
