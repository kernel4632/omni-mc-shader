/*
效果文件 `effects/water/caustics.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/water/caustics.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_CAUSTICS_INCLUDED
#define OMNI_CAUSTICS_INCLUDED
/*
焦散：算出水面波的八面体编码法线，写进七号画面，供合成阶段做水面焦散与水下体积雾采样。
调用位置：`rendering/deferred.glsl` 的延迟零号（主世界）与延迟一号（末地）片元分支引入本文件；
    这两个程序的片元 `main()` 调用 `RenderCaustics()` 写七号画面。
可复制示例：
    `void main(){ RenderCaustics(); }`   在已声明七号输出 `deferredOutput7` 的延迟程序里调用。
调用前提：调用方必须先声明全局量 `texelCoord`、`texCoord` 与输出 `deferredOutput7`，
    并引入 `common/math.glsl`（`EncodeNormal` 与常数）与 `effects/fog/fog.glsl`（提供 `GetWavesNormal`）；
    本文件不重复声明，参照 `effects/sky/sky.glsl` 的调用约定。
设计原因与取舍：
    主世界延迟零号与末地延迟一号的焦散公式逐行相同，只差一个丢弃判断：主世界在不看焦散又不做水下体积雾时整片丢弃，
    省掉一次全屏波浪计算；这个差别用调用程序宏 `OMNI_DEFERRED0_PASS` 区分，行为与原来完全一致。
    平移进一个函数后，两个程序共用同一段算法，不再各存一份；编号与用途见 `rendering/buffers.glsl` 的七号画面。
*/

// --- 延迟零号（主世界）、延迟一号（末地）片元主体 ---
// 当前像素的屏幕坐标先按屏幕高度与方块上限缩放，再求波法线，最后八面体编码写进七号画面。
void RenderCaustics(){
	#if defined OMNI_DEFERRED0_PASS // 主世界延迟零号：既不开焦散又不开水下体积雾时没人读这张图，整片丢弃。
		#if !defined OMNI_CAUSTICS && (!defined OMNI_VFOG || !defined OMNI_UNDERWATER_VFOG)
			discard; // 丢弃不需要的像素，省掉后面的波浪计算。
		#endif
	#endif
	const float maxCausticsNormalHeight = CAUSTICS_TEX_RESOLUTION; // 方块边长上限，来自内部常数。
	vec3 screenCaustics = vec3(0.0, 0.0, 1.0); // 默认朝上的波法线。
	vec2 causticsCoord = gl_FragCoord.xy * (50.0 / min(screenSize.y, maxCausticsNormalHeight)); // 把屏幕坐标换算到波浪空间。
	screenCaustics = GetWavesNormal(vec3(causticsCoord.x, 1.0, causticsCoord.y), 25.0).xyz; // 求该处的波法线。
	deferredOutput7 = vec4(EncodeNormal(screenCaustics), 0.0, 0.0); // 八面体编码后写进七号。
}
#endif // OMNI_CAUSTICS_INCLUDED
