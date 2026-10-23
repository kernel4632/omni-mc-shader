/*
季节的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/weather/season.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_WEATHER_SEASON_INCLUDED
#define OMNI_RENDER_WEATHER_SEASON_INCLUDED
#include "/effects/weather/season.glsl"
/*
季节：让草地、树叶、藤蔓这类按生物群系染色的植被随游戏天数缓慢变色，做出春夏秋冬的观感。
来源：Omni 自己的额外功能，iterationT 没有对应算法，保留既有做法并接到新管线。
调用位置：几何阶段地形片元的底色解出之后、进入光照之前，调用 `albedo = omniSeason(albedo, color);`；
  默认关闭，关闭时原样返回，画面与 iterationT 一致。
可复制示例：
  `albedo = omniSeason(albedo, v_color);`  `v_color` 是加载器给地形顶点的顶点色。
调用前提：世界天数 `worldDay` 由 `common/uniforms.glsl` 统一声明；只应在地形片元里调用。
设计原因与取舍：
  哪些面算植被看加载器给的顶点色。原版只给草方块顶面、草、蕨、树叶、藤蔓这类乘上群系的绿色，
  普通方块与花的顶点色接近白色，水的顶点色偏蓝，所以“绿比红、蓝都多”就是植被，不必列方块编号。
  颜色变化只来自世界天数，不读生物群系，因此任何世界都能用；它是整体近似，不区分具体群系。
*/
// 世界天数 `worldDay` 由加载器提供，已在 `common/uniforms.glsl` 声明，这里不重复声明。
#include "/common/uniforms.glsl"
// 植被判断与季节上色放在通用库，这里只传入游戏日与选项。
#include "/gfx/weather.glsl"
// 植被程度：顶点色里绿色比红、蓝多出越多，越像群系染过的植被；白色方块与偏蓝的水都得零。
float omniFoliage(vec3 vertexColor){
	return gfx_foliage(vertexColor); // 转发到通用库。
}
// 季节上色：植被按一年的相位混入秋色，再按选项整体偏暖或偏冷；非植被原样返回。
// 调用前提：只在地形片元调用，`vertexColor` 是加载器给该顶点的顶点色。
vec3 omniSeason(vec3 albedo, vec3 vertexColor){
	#if OMNI_SEASONS // 关闭时只传假值，库里原样返回。
		return gfx_season(albedo, vertexColor, fract(float(worldDay) / 24.0), OMNI_SEASON_TINT, true);
	#else
		return gfx_season(albedo, vertexColor, 0.0, OMNI_SEASON_TINT, false);
	#endif
}
#endif // OMNI_RENDER_WEATHER_SEASON_INCLUDED
