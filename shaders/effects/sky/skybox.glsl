/*
天空盒投影：把世界方向与天空盒三维贴图上的纹素坐标互相换算，供写天空盒图与顶点阶段回读云量。
调用位置：由 `effects/sky/sky.glsl` 引入；延迟三号写上半屏天空盒图时调用 `UnprojectSky`，
    合成与延迟顶点阶段投光方向读取云量时调用 `ProjectSky`。
可复制示例：
    `vec3 dir = UnprojectSky(skyImageTexel, tileSize);`
    `vec2 skyUv = ProjectSky(worldShadowVector, tileSize);`
设计原因与取舍：天空盒贴图排成三乘二张面，投影与反投影互为逆；原程序在屏幕空间反射与天空两处各写一份，
    按移植合同只在天空效果里保留一份，这里继续保留唯一一份。
*/
#ifndef OMNI_SKY_SKYBOX_INCLUDED
#define OMNI_SKY_SKYBOX_INCLUDED
// 把天空盒三维贴图上的一个纹素坐标反解成世界方向，与 `ProjectSky` 互为逆。
vec3 UnprojectSky(vec2 texel, float tileSize){
	float tileSizeDivide = 1.0 / (0.5 * tileSize - 1.5); // 纹素到方向的缩放系数。
	vec3 direction = vec3(0.0); // 待求的世界方向。
	if (texel.x < tileSize) { // 第一张面，朝 x 正负。
		direction.x = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
		direction.y = (texel.x - tileSize * 0.5) * tileSizeDivide; // 横坐标映射到一个轴。
		direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
	} else if (texel.x < 2.0 * tileSize) { // 第二张面，朝 y 正负。
		direction.x = (texel.x - tileSize * 1.5) * tileSizeDivide; // 横坐标映射到一个轴。
		direction.y = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
		direction.z = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
	} else { // 第三张面，朝 z 正负。
		direction.x = (texel.x - tileSize * 2.5) * tileSizeDivide; // 横坐标映射到一个轴。
		direction.y = (texel.y - tileSize * (step(tileSize, texel.y) + 0.5)) * tileSizeDivide; // 纵坐标映射到另一个轴。
		direction.z = step(tileSize, texel.y) * 2.0 - 1.0; // 纵半决定正负。
	}
	return normalize(direction); // 单位世界方向。
}
// 把一个世界方向投到天空盒三维贴图上，与 `UnprojectSky` 互为逆；原程序两处各写一份，按合同只保留这里一份。
// 调用前提：`screenSize` 与 `pixelSize` 已由绘制主体声明。
vec2 ProjectSky(vec3 dir, float tileSize){
	float tileSizeDivide = 0.5 * tileSize - 1.5; // 方向到纹素的缩放系数。
	vec3 adir = abs(dir); // 三个分量的绝对值，用来选主轴。
	vec2 texel; // 待求的纹素坐标。
	if (adir.x > adir.y && adir.x > adir.z){ // x 份量最大时用第一张面。
		dir /= adir.x; // 归一化主轴分量。
		texel.x = dir.y * tileSizeDivide + tileSize * 0.5; // 一个轴映射到横坐标。
		texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.x) + 0.5); // 另一个轴映射到纵坐标，符号决定上下半。
	}else if (adir.y > adir.x && adir.y > adir.z){ // y 分量最大时用第二张面。
		dir /= adir.y; // 归一化主轴分量。
		texel.x = dir.x * tileSizeDivide + tileSize * 1.5; // 偏移到第二张面。
		texel.y = dir.z * tileSizeDivide + tileSize * (step(0.0, dir.y) + 0.5); // 符号决定上下半。
	}else{ // 否则用第三张面。
		dir /= adir.z; // 归一化主轴分量。
		texel.x = dir.x * tileSizeDivide + tileSize * 2.5; // 偏移到第三张面。
		texel.y = dir.y * tileSizeDivide + tileSize * (step(0.0, dir.z) + 0.5); // 符号决定上下半。
	}
	texel.y += ceil(screenSize.y * 0.5 + 1.0); // 天空盒贴图放在上半屏，纵坐标抬到上半屏起点。
	return texel * pixelSize; // 纹素坐标换成零到一的贴图坐标。
}
#endif // 文件守卫结束。
