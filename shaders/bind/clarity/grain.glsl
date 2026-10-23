/*
胶片颗粒的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/clarity/grain.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_CLARITY_GRAIN_INCLUDED
#define OMNI_BIND_CLARITY_GRAIN_INCLUDED
#include "/effects/clarity/grain.glsl"
/*
胶片颗粒：给最终显示画面叠加一层随时间变化的细噪点，模拟胶片感光颗粒。
来源：算法照 Eclipse `dimensions/final.fsh` 的 `FILM_GRAIN` 段一比一移植（原实现注明参考一个在线着色器示例）。
调用位置：`rendering/post.glsl` 的合成十四号片元在 `TonemapColor()` 写出一号画面之后调用 `OmniFilmGrain`，
    此时颜色已完成色调映射、处于显示空间，与 Eclipse 在 `final.fsh` 里叠加颗粒的位置一致。
可复制示例：`color = OmniFilmGrain(color, texCoord);`
调用前提：调用方需已提供共享声明里的零到一屏幕坐标 `texCoord`；本文件自己引入加载器输入取时间量。
设计原因与取舍：
    颗粒把屏幕坐标与累计秒数乘成一个种子，再用两次取模相乘折成一个小数；换屏幕位置或换帧都不同，形成流动的噪点，代价很低。
    时间来源用绑定层的累计秒数（原加载器输入 `frameTimeCounter`），与 Eclipse 同名同义；Omni 另有每帧递增的 `frameCounter`，这里不用它，
    是为了和原实现保持同一时间来源，避免两边画面随时间变化的速度不同。
    颗粒加在色调映射之后，幅度只有千分之几，默认关闭，不改变当前画面。
    已知取舍：合成十四号之后还有可选的放大链路（合成十五号锐化、合成十六号放大），开启放大时颗粒会被一起放大而略微变淡；
    默认渲染比例为一、不走放大，画面不受影响。
默认状态：`OMNI_FILM_GRAIN` 关闭（与原程序注释掉的 `FILM_GRAIN` 一致），`OMNI_FILM_GRAIN_STRENGTH` 默认 2.5。
*/
// 加载器输入由绑定层整理，时间以普通秒数交给效果。
#include "/bind/time.glsl"
// 颗粒公式放在通用库。
#include "/gfx/post.glsl"

// --- 胶片颗粒：把屏幕坐标与时间合成一个种子，再折成一个正负各半的细噪点 ---
// 为什么用取模反复折叠：原实现只用取模和乘法把坐标与时间搅成一个伪随机数，不做噪声贴图采样，代价很低。
// 为什么乘零点零一再减零点零零五：让结果落在正负零点零零五之间，围绕零上下波动，只加噪点而不整体提亮或压暗画面。
vec3 OmniFilmGrain(vec3 color, vec2 coord){
	#if OMNI_FILM_GRAIN // 关闭时整段不编译，直接原样返回。
		color = gfx_film_grain(color, coord, bind_time().seconds, OMNI_FILM_GRAIN_STRENGTH); // 颗粒公式在通用库，时间与强度在这里传入。
	#endif
	return color; // 返回叠加颗粒后的颜色，关闭时就是原颜色。
}
#endif // OMNI_BIND_CLARITY_GRAIN_INCLUDED
