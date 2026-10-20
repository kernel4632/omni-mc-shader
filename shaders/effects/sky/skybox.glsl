/*
天空盒投影：把世界方向与天空盒三维贴图上的纹素坐标互相换算，供写天空盒图与顶点阶段回读云量。
调用位置：由 `effects/sky/sky.glsl` 引入；延迟三号写上半屏天空盒图时调用 `UnprojectSky`，
    合成与延迟顶点阶段投光方向读取云量时调用 `ProjectSky`。
可复制示例：
    `vec3 dir = UnprojectSky(skyImageTexel, tileSize);`
    `vec2 skyUv = ProjectSky(worldShadowVector, tileSize);`
设计原因与取舍：天空盒贴图排成三乘二张面，投影与反投影互为逆；原程序在屏幕空间反射与天空两处各写一份，
    按移植合同只在天空效果里保留一份，这里继续保留唯一一份。
    两个方向的换算已经迁到 `shaders/gfx/atmosphere.glsl`，本文件只补屏幕上半屏的贴图偏移与像素换算。
*/
#ifndef OMNI_SKY_SKYBOX_INCLUDED
#define OMNI_SKY_SKYBOX_INCLUDED
// 天空盒方向与纹素换算放在通用库，这里只传单面边长。
#include "/gfx/atmosphere.glsl"
// 把天空盒三维贴图上的一个纹素坐标反解成世界方向，与 `ProjectSky` 互为逆。
vec3 UnprojectSky(vec2 texel, float tileSize){
	return gfx_sky_unproject(texel, tileSize); // 转发到通用库。
}
// 把一个世界方向投到天空盒三维贴图上，与 `UnprojectSky` 互为逆；原程序两处各写一份，按合同只保留这里一份。
// 调用前提：`screenSize` 与 `pixelSize` 已由绘制主体声明。
vec2 ProjectSky(vec3 dir, float tileSize){
	vec2 texel = gfx_sky_project(dir, tileSize); // 先算三乘二贴图内的纹素坐标。
	texel.y += ceil(screenSize.y * 0.5 + 1.0); // 天空盒贴图放在上半屏，纵坐标抬到上半屏起点。
	return texel * pixelSize; // 纹素坐标换成零到一的贴图坐标。
}
#endif // 文件守卫结束。
