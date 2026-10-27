/*
效果文件 `effects/water/eclipse_bump_adapters.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/water/eclipse_bump_adapters.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_WATER_ECLIPSE_BUMP_INCLUDED
#define OMNI_EFFECT_WATER_ECLIPSE_BUMP_INCLUDED
/*
Eclipse 水面波函数兼容层：参考直接读噪声贴图与时间，宿主层用同名重载补齐。
调用位置：由 `rendering/water/water.glsl` 在通用水面库之后引入。
可复制示例：`float caustics = waterCaustics(worldPos, sunVec, surfacePos);`
设计原因与取舍：参考的波尺寸数组与旋转写在函数内部；库把尺寸、时间与混合系数显式化。
    本文件只把默认值接回去，不改波算法。循环展开与否不影响实际采样次数，库为性能已展开。
*/

// 水面焦散：时间、波速与干湿混合取参考默认值。
float waterCaustics(vec3 worldPos, vec3 sunVec, float surfacePos){
	return ogxWaterBumpCaustics(worldPos, sunVec, surfacePos, frameTimeCounter, 1.0, 1.0, noisetex);
}
// 水面高度：同样取参考默认时间与波速。
float getWaterHeightmap(vec2 posxz, float largeWavesCurved, float radiance){
	return ogxWaterBumpHeightmap(posxz, largeWavesCurved, frameTimeCounter, 1.0, noisetex);
}
// 水面法线：参考用玩家位置决定远处波幅，这里显式传入；两个波半径取参考默认一与零点一五。
vec3 getWaveNormal(vec3 waterPos, vec3 playerpos){
	return ogxWaterBumpNormal(waterPos, playerpos, frameTimeCounter, 1.0, 1.0, 1.0, 0.15, false, noisetex);
}

#endif // Eclipse 水面波兼容层结束。

// 严格对照补充说明：
// Eclipse 水面波函数直接读噪声贴图、帧时间与两个波半径。
// 宿主层把时间、波速、干湿混合与波半径显式传入通用库。
// 波尺寸数组仍是参考的四十八、十二与三十二，循环顺序不变。
// 水面焦散、高度图与法线共用同一套噪声，避免三处常数各改各的。
// 这些函数只依赖噪声贴图与时间，不需要相机或阴影缓冲。
// 兼容重载保留参考名称，渲染主体仍可调用原来的显式参数版本。
