/*
最终显示：把时间合成后的线性场景变成屏幕上一帧最终颜色，并在调试时改看中间数据。
它是整个绘制流程的最后一站，最后一步结果直接进屏幕。

调用位置：
  三个维度的 final 顶点与像素入口经 include 引入本文件；
  像素入口定义 OMNI_FRAGMENT 走下面的函数，顶点入口定义 OMNI_VERTEX 只负责铺满屏幕。

可复制示例：
  像素入口自动调用 main，无需手工触发；
  想单独取一帧线性颜色：`vec3 scene = omniSceneColor(texcoord);`

显示顺序（为什么是这个顺序）：
  一、超分：内部渲染分辨率低于输出时先重采样，之后的计算都在输出分辨率上进行。
  二、镜头与泛光：色差、景深、耀斑、暗角是作用在场景本身的成像变形，
      泛光是在此之上叠加的光晕，所以放在镜头之后，不跟着被暗角压暗；两者都在线性空间，方便直接相加。
  三、调色与显示编码：omniColor 内部完成曝光、高光压缩和屏幕编码，
      编码把所有线性计算收敛成屏幕颜色，必须最后做且只做一次，否则颜色会被反复压暗。
  四、调试：debugColor 直接观察真实中间缓冲，放在最后；正常画面时它原样返回，不改变结果。

关键设计取舍：
  显示阶段不新增任何中间画面，只读时间合成留下的线性颜色和曝光；
  超分是唯一可选的额外取样步骤，默认关闭，关闭时它不产生任何额外开销。
*/
#ifdef OMNI_VERTEX
out vec2 texcoord; // 传给像素阶段的屏幕坐标，范围零到一。
void main() { gl_Position = ftransform(); texcoord = gl_MultiTexCoord0.xy; } // 铺满屏幕的最终四边形。
#endif
#ifdef OMNI_FRAGMENT
// 最终显示用到的效果能力，一行引入一个主体，顺序与上面说明一致。
#include "/effects/color.glsl"
#include "/effects/bloom.glsl"
#include "/effects/lens.glsl"
#include "/effects/upscale.glsl"
#include "/effects/debug.glsl"
#include "/rendering/buffers.glsl"
in vec2 texcoord; // 像素阶段的屏幕坐标，与顶点阶段同名传入。
layout(location=0) out vec4 color; // 写入默认画面缓冲的最终屏幕颜色。

// --- 取这一帧的线性颜色 ---

// 取最终显示要用的线性颜色：从时间合成写回的附件读取，玩家开启超分时先对颜色重采样。
// 为什么超分放在最前：它是分辨率相关的重采样，后面的镜头泛光都按输出分辨率计算，顺序反了会先糊再算。
vec3 omniSceneColor(vec2 uv) {
    vec3 scene = texture(colortex0,uv).rgb; // 时间合成写回零号附件的线性颜色，范围可以高于一。
#ifdef OMNI_UPSCALE
    scene = omniUpscale(scene,uv); // 只有开启超分时才做边缘自适应重采样，关闭时不产生任何开销。
#endif
    return scene; // 返回仍是线性空间、尚未压缩的颜色，交给后面的效果。
}

// --- 在线性空间叠加镜头与泛光 ---

// 在给定的线性颜色上叠加镜头与泛光：镜头改造场景本身的成像，泛光再把强光的光晕加回去。
// 为什么泛光在镜头之后：暗角和色差只该作用在场景成像上，光晕是最后叠上去的附加亮光，
// 若先加泛光，暗角会把它一起压暗，亮部光晕就不自然。
vec3 omniLensColor(vec3 scene, vec2 uv) {
    return omniLens(scene,uv)+omniBloom(uv); // 两者都在线性空间相加，不会引入偏色。
}

// --- 一个像素的最终显示 ---

// 像素阶段主流程：取线性颜色、叠加镜头泛光、按曝光调色编码，最后输出或改看调试数据。
// 为什么调色放最后：它内部包含曝光和屏幕编码，编码必须在所有线性计算之后才做，且只做一次。
void main() {
    vec3 scene = omniSceneColor(texcoord); // 时间合成的线性颜色，可选超分。
    vec3 lit = omniLensColor(scene,texcoord); // 镜头与泛光仍在线性空间叠加。
    float exposure = texture(colortex5,vec2(0.5)).g; // 时间合成保存的真实曝光，整屏共用一个值。
    vec3 shown = omniColor(lit,exposure); // 调色把线性颜色压成屏幕颜色，显示编码包含在内。
    color = vec4(debugColor(shown,texture(depthtex0,texcoord).r,texcoord),1.0); // 调试视图观察真实缓冲，正常画面原样返回。
}
#endif
