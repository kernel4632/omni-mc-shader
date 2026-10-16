/*
季节：让草地、树叶、藤蔓这类按生物群系染色的植被随游戏天数缓慢变色，做出春夏秋冬的观感。
来源：Omni 自己的额外功能，iterationT 没有对应算法，保留既有做法并接到新管线。
调用位置：几何阶段地形片元的底色解出之后、进入光照之前，调用 `albedo = omniSeason(albedo, color);`；
  默认关闭，关闭时原样返回，画面与 iterationT 一致。
可复制示例：
  `albedo = omniSeason(albedo, v_color);`  `v_color` 是加载器给地形顶点的顶点色。
调用前提：本文件自己声明世界天数 `worldDay`，并引入加载器输入；只应在地形片元里调用。
设计原因与取舍：
  哪些面算植被看加载器给的顶点色。原版只给草方块顶面、草、蕨、树叶、藤蔓这类乘上群系的绿色，
  普通方块与花的顶点色接近白色，水的顶点色偏蓝，所以“绿比红、蓝都多”就是植被，不必列方块编号。
  颜色变化只来自世界天数，不读生物群系，因此任何世界都能用；它是整体近似，不区分具体群系。
*/
#ifndef OMNI_SEASON_INCLUDED // 只引入一次，避免选项重复定义。
#define OMNI_SEASON_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"季节","en_us":"Seasons"}}
// @option {"label":{"zh_cn":"季节开关","en_us":"Seasons"},"description":{"zh_cn":"草地、树叶和藤蔓的颜色随游戏天数缓慢变化；默认关闭，不影响默认画面。","en_us":"Grass, leaf and vine colour shifts with the in-game day count; off by default so the default look is unchanged."}}
//#define OMNI_SEASONS
// @option {"label":{"zh_cn":"季节颜色","en_us":"Season Colour"},"description":{"zh_cn":"正值偏暖偏秋黄，负值偏冷偏绿。","en_us":"Positive leans warm autumn-yellow, negative leans cool green."},"slider":true}
#define OMNI_SEASON_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// 世界天数由加载器提供；加载器输入声明里没有它，所以在本文件声明一次。
#include "/common/uniforms.glsl"
uniform int worldDay; // 当前游戏天数，季节相位由它推得。
// 植被程度：顶点色里绿色比红、蓝多出越多，越像群系染过的植被；白色方块与偏蓝的水都得零。
float omniFoliage(vec3 vertexColor){
	return clamp((vertexColor.g - max(vertexColor.r, vertexColor.b)) * 4.0, 0.0, 1.0); // 乘四让普通草色就能接近一，再夹到零到一。
}
// 季节上色：植被按一年的相位混入秋色，再按选项整体偏暖或偏冷；非植被原样返回。
// 调用前提：只在地形片元调用，`vertexColor` 是加载器给该顶点的顶点色。
vec3 omniSeason(vec3 albedo, vec3 vertexColor){
	#ifdef OMNI_SEASONS // 关闭时原样返回，不改变默认画面。
		float foliage = omniFoliage(vertexColor); // 这一面有多像植被。
		float phase = fract(float(worldDay) / 24.0); // 一年按二十四个游戏日循环。
		float autumn = 0.5 - 0.5 * cos(phase * 6.283185); // 在零到一之间缓慢摆动，一年过半时最接近秋天。
		vec3 seasonal = mix(vec3(1.0), vec3(1.15, 0.9, 0.5), autumn * 0.6); // 秋色最多混六成，保留原本的绿。
		seasonal *= vec3(1.0 + 0.2 * OMNI_SEASON_TINT, 1.0, 1.0 - 0.2 * OMNI_SEASON_TINT); // 季节颜色整体偏暖或偏冷。
		albedo *= mix(vec3(1.0), seasonal, foliage); // 只按植被程度生效，边缘不会突然变色。
	#endif
	return albedo; // 交回处理后的底色。
}
#endif // 文件守卫结束。
