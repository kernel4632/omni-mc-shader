/*
效果文件 `effects/dev/debug.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/dev/debug.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_DEV_DEBUG_INCLUDED
#define OMNI_EFFECT_DEV_DEBUG_INCLUDED
// @effect {"label":{"zh_cn":"开发调试","en_us":"Development"}}
// @option {"label": {"zh_cn": "调试显示", "en_us": "Debug view"}, "description": {"zh_cn": "0：正常画面；1：几何法线；2：深度；3：光照图。用现有中间画面直接观察，关闭时画面不变。", "en_us": "0: scene; 1: geometry normals; 2: depth; 3: lightmap. Reads existing buffers directly; off keeps the scene."}, "values": {"0": {"zh_cn": "正常画面", "en_us": "Scene"}, "1": {"zh_cn": "几何法线", "en_us": "Normals"}, "2": {"zh_cn": "深度", "en_us": "Depth"}, "3": {"zh_cn": "光照图", "en_us": "Lightmap"}}}
#define OMNI_DEBUG_VIEW 0 // [0 1 2 3]
// @option {"label":{"zh_cn":"性能计时","en_us":"Frame-time bar"},"description":{"zh_cn":"在屏幕左下角画一条横条显示每帧耗时，越长越慢；这是整帧时间，不是逐效果耗时。","en_us":"Draws a bar in the bottom-left showing per-frame time; this is total frame time, not per-effect."}}
#define OMNI_PROFILER 0 // [0 1]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
调试显示：保留 Omni 自己的调试视图与帧耗时条，二者都以中性默认接入，默认不改变玩家画面。
调用位置：`rendering/final.glsl` 的片元 `main()` 最后调用 `debugColor` 与 `omniProfiler`，
  把最终屏幕颜色替换成调试画面或叠上耗时条。
可复制示例：`color = debugColor(color, textureLod(depthtex0, texCoord, 0.0).x, texCoord);`  按选项换成法线、深度或光照图；
  `color = omniProfiler(color, texCoord);`
调用前提：`debugColor` 读取 `colortex4` 与传入深度，调用方要保证它们在当前程序里可见。
设计原因与取舍：默认关闭全部调试输出（`OMNI_DEBUG_VIEW` 为零、`OMNI_PROFILER` 未定义），
  调试代码本身不进入正常画面，关闭时画面与 iterationT 完全一致；
  说明：原程序用来在屏幕上打印数值的七段数码管（`PrintFloat` 一族）在 iterationT 的 `main` 里从未被调用，
  本项目也一直没有任何调用点，属于死代码，按项目规范删除，记录见 `docs/parity.md` 的偏离清单。
*/
// 加载器输入提供中间画面与画面尺寸，调试视图按编号读取它们。
#include "/common/uniforms.glsl"
// 法线解码 `DecodeNormal` 来自共用数学，调试视图用它把打包法线还原成可见颜色。
#include "/common/math.glsl"

// 说明：以上七段数码管一族（字模表、`SevenSegment`、`DecimalPoint`、`PrintFloat`、`PrintUintBinary`）
// 在 iterationT 里就没有被任何 `main` 调用，本项目也没有调用点，属于死代码，按项目规范删除。
// 需要再读数值时可从 iterationT 的 `Lib/IndividualFounctions/PrintFloat.glsl` 取回，或改用调试视图。

// --- Omni 额外功能：帧耗时条 ---
// 性能计时：加载器只给整帧耗时，没有逐效果计时，所以这里只画一条按耗时长短变化的横条。
// 满格约三十三毫秒；快帧偏绿、慢帧偏红，方便一眼看出卡顿。
vec3 omniProfiler(vec3 color, vec2 coordinates){
#if OMNI_PROFILER // 关闭时不画任何东西。
	vec2 pixel = coordinates*vec2(viewWidth,viewHeight); // 屏幕像素坐标，左下角为原点。
	float filled = clamp(frameTime*1000.0/33.0,0.0,1.0); // 把毫秒换算成零到一的填充比例。
	if (pixel.x < 160.0 && pixel.y < 8.0) { // 只画左下角一小块，不遮挡画面主体。
		float lit = pixel.x/160.0 < filled ? 1.0 : 0.0; // 横条以内是点亮的像素。
		color = mix(vec3(0.04),mix(vec3(0.2,0.9,0.35),vec3(0.95,0.2,0.2),filled),lit); // 快帧偏绿、慢帧偏红。
	}
#endif
	return color; // 未开启时原样返回。
}

// --- Omni 额外功能：选择要观察的中间数据 ---
// 按选项把最终场景颜色换成法线、深度或光照图，帮助定位绘制问题。
// 为什么用四号画面：延迟六号把不透明法线光照图复制进四号，半透明层也会写入它，到最终阶段仍可读；
// 深度用不含半透明的 `depthtex0`，法线用 `DecodeNormal` 还原成方向后映射到零到一以便肉眼分辨。
// 默认零表示不改变玩家画面，所以这个功能是中性接入，关闭时与 iterationT 完全一致。
vec3 debugColor(vec3 scene, float depth, vec2 coordinates){
#if OMNI_DEBUG_VIEW == 1 // 几何法线：四号画面的 `rg` 通道是打包法线。
	return DecodeNormal(texture(colortex4, coordinates).xy) * 0.5 + 0.5; // 解出方向后映射到零到一显示。
#elif OMNI_DEBUG_VIEW == 2 // 深度：直接看加载器提供的深度。
	return vec3(depth); // 用灰度展示。
#elif OMNI_DEBUG_VIEW == 3 // 光照图：四号画面的 `ba` 通道是方块光与天光。
	return vec3(texture(colortex4, coordinates).ba, 0.0); // 红绿通道分别显示方块光与天光。
#else
	return scene; // 默认不改变玩家画面。
#endif
}
#endif // OMNI_EFFECT_DEV_DEBUG_INCLUDED
