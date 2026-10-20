/*
世界绑定：把维度、太阳方向和阴影光源方向整理成普通结构体，供天空、雾与体积效果共用。
调用位置：需要判断维度或把光方向换到世界空间的效果在边界调用 `bind_world()`。
可复制示例：`vec3 sunDir = bind_world().sunDirection;`
设计原因与取舍：加载器给的太阳方向在视空间，效果通常要世界空间，这里统一转换一次，
  避免每个文件各写一遍 `mat3(gbufferModelViewInverse) * sunPosition` 而漏掉归一化；
  维度编号固定为主世界零、末地一、下界负一，编译时由入口宏决定，运行时不额外传参。
*/
#ifndef OMNI_BIND_WORLD_INCLUDED // 只引入一次，避免结构体与函数重复定义。
#define OMNI_BIND_WORLD_INCLUDED // 置上标记，后续再次引用直接跳过。
// 世界输入只在加载器声明文件里出现一次。
#include "/common/uniforms.glsl"

struct OmniWorld {
	int dimension; // 维度编号：主世界零、末地一、下界负一。
	vec3 sunDirection; // 世界空间的太阳或月亮方向，已归一化。
	vec3 shadowDirection; // 世界空间的阴影光源方向，已归一化。
	mat4 shadowView; // 世界到阴影相机视空间。
	mat4 shadowProjection; // 阴影相机投影。
	mat4 shadowViewInverse; // 阴影相机视空间回到世界。
};

// 按入口宏判断当前维度；同一份代码被三个世界入口分别编译。
int bind_dimension(){
#if defined OMNI_NETHER // 下界入口。
	return -1; // 下界用负一。
#elif defined OMNI_END // 末地入口。
	return 1; // 末地用一。
#else // 其余入口按主世界处理。
	return 0; // 主世界用零。
#endif
}

// 读取本帧的世界与阴影输入；只做打包和空间转换，不改变颜色。
OmniWorld bind_world(){
	OmniWorld world; // 待填充的结构体。
	world.dimension = bind_dimension(); // 编译时确定的维度编号。
	world.sunDirection = normalize(mat3(gbufferModelViewInverse) * sunPosition); // 视空间转到世界空间并归一化。
	world.shadowDirection = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition); // 阴影光源同样转世界空间。
	world.shadowView = shadowModelView; // 阴影视图。
	world.shadowProjection = shadowProjection; // 阴影投影。
	world.shadowViewInverse = shadowModelViewInverse; // 阴影逆视图。
	return world; // 返回纯数据，调用方不需要知道来源。
}
#endif // 世界绑定结束。
