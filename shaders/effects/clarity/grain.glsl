/*
效果文件 `effects/clarity/grain.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/clarity/grain.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_CLARITY_GRAIN_INCLUDED
#define OMNI_EFFECT_CLARITY_GRAIN_INCLUDED
// @effect {"label":{"zh_cn":"胶片颗粒","en_us":"Film Grain"}}
// @option {"label":{"zh_cn":"胶片颗粒","en_us":"Film Grain"},"description":{"zh_cn":"给画面叠加随时间变化的细噪点，模拟胶片感光颗粒；默认关闭。","en_us":"Adds animated fine noise to mimic film grain; off by default."}}
#define OMNI_FILM_GRAIN 0 // [0 1]
// @option {"label":{"zh_cn":"颗粒强度","en_us":"Grain Strength"},"slider":true,"description":{"zh_cn":"颗粒的幅度，越大噪点越明显；参考值约二点五。","en_us":"Amplitude of the grain; about 2.5 is a moderate amount."}}
#define OMNI_FILM_GRAIN_STRENGTH 2.5 // [0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
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
#include "/omni-gfx/post/post.glsl"

// --- 胶片颗粒：把屏幕坐标与时间合成一个种子，再折成一个正负各半的细噪点 ---
// 为什么用取模反复折叠：原实现只用取模和乘法把坐标与时间搅成一个伪随机数，不做噪声贴图采样，代价很低。
// 为什么乘零点零一再减零点零零五：让结果落在正负零点零零五之间，围绕零上下波动，只加噪点而不整体提亮或压暗画面。
vec3 OmniFilmGrain(vec3 color, vec2 coord){
	#if OMNI_FILM_GRAIN // 关闭时整段不编译，直接原样返回。
		color = ogxFilmGrain(color, coord, bind_time().seconds, OMNI_FILM_GRAIN_STRENGTH); // 颗粒公式在通用库，时间与强度在这里传入。
	#endif
	return color; // 返回叠加颗粒后的颜色，关闭时就是原颜色。
}
#endif // OMNI_EFFECT_CLARITY_GRAIN_INCLUDED
