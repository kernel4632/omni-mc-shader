/*
季节：让草地、树叶、藤蔓这类按生物群系染色的植被随游戏天数缓慢变色，做出春夏秋冬的观感。

调用位置：rendering/terrain.glsl 的 omniShadeSurface，在线性底色之后、光照之前调用。
可复制示例：`albedo = omniSeason(albedo, tint.rgb);`

设计原因与取舍：
  哪些面算植被：看加载器给的顶点色。原版只给草方块顶面、草、蕨、树叶、藤蔓这类植被乘上群系的绿色，
  普通方块和花的顶点色接近白色，水的顶点色偏蓝。所以“绿比红、蓝都多”就是植被，不需要列方块编号，
  草方块顶面和树叶会一起变色，花不会被染黄。
  颜色变化来自世界天数，不读生物群系，所以任何世界里都能用，但它是整体近似，不区分具体群系。
*/
#ifndef OMNI_SEASON_INCLUDED
#define OMNI_SEASON_INCLUDED
// @effect {"label":{"zh_cn":"季节","en_us":"Seasons"}}
// @option {"label":{"zh_cn":"季节开关","en_us":"Seasons"},"description":{"zh_cn":"草地、树叶和藤蔓的颜色随游戏天数缓慢变化。","en_us":"Grass, leaf and vine colour shifts with the in-game day count."}}
//#define OMNI_SEASONS
// @option {"label":{"zh_cn":"季节颜色","en_us":"Season colour"},"description":{"zh_cn":"正值偏暖偏秋黄、负值偏冷偏绿。","en_us":"Positive leans warm autumn-yellow, negative leans cool green."},"slider":true}
#define OMNI_SEASON_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// 世界天数来自统一输入。
#include "/common/uniforms.glsl"
// 植被程度：顶点色里绿色比红、蓝多出越多，越像群系染过的植被；白色方块和偏蓝的水都得零。
float omniFoliage(vec3 vertexColor) {
    return clamp((vertexColor.g - max(vertexColor.r, vertexColor.b)) * 4.0, 0.0, 1.0); // 乘四让普通草色就能接近一。
}
// 季节上色：植被按一年的相位混入秋色，再按选项整体偏暖或偏冷；非植被原样返回。
vec3 omniSeason(vec3 albedo, vec3 vertexColor) {
#ifdef OMNI_SEASONS
    float foliage = omniFoliage(vertexColor); // 这一面有多像植被。
    float phase = fract(float(worldDay) / 24.0); // 一年按二十四个游戏日循环，天数是加载器给的真实计数。
    float autumn = 0.5 - 0.5 * cos(phase * 6.283185); // 在零到一之间缓慢摆动，一年过半时最接近秋天。
    vec3 seasonal = mix(vec3(1.0), vec3(1.15, 0.9, 0.5), autumn * 0.6); // 秋色最多混六成，保留原本的绿。
    seasonal *= vec3(1.0 + 0.2 * OMNI_SEASON_TINT, 1.0, 1.0 - 0.2 * OMNI_SEASON_TINT); // 季节颜色整体偏暖或偏冷。
    albedo *= mix(vec3(1.0), seasonal, foliage); // 只按植被程度生效，边缘不会突然变色。
#endif
    return albedo; // 关闭季节时原样返回。
}
#endif
