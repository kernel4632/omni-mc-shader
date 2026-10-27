/*
效果文件 `effects/reflection/voxel.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/reflection/voxel.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_REFLECTION_VOXEL_INCLUDED
#define OMNI_EFFECT_REFLECTION_VOXEL_INCLUDED
// @effect {"label":{"zh_cn":"体素反射","en_us":"Voxel reflections"}}
// @option {"label":{"zh_cn":"体素反射","en_us":"Voxel reflections"},"description":{"zh_cn":"在体素图上追踪反射，屏幕空间反射没命中的地方用体素里的方块颜色补上；只在主世界生效，缺自定义图像能力时不参与编译，关闭时画面不变。","en_us":"Traces reflections through the voxel grid and fills screen-space misses with stored block colours; overworld only, off keeps the picture unchanged."}}
#define OMNI_VOXEL_REFLECTION 0 // [0 1]
// @option {"label":{"zh_cn":"追踪距离","en_us":"Trace distance"},"description":{"zh_cn":"体素反射最远能打多远，越大越能反射远处地形，也更慢。","en_us":"How far voxel reflections reach; larger reflects more distant terrain but is slower."},"slider":true}
#define OMNI_VOXEL_REFLECTION_DISTANCE 64 // [32 48 64 96]
// @option {"label":{"zh_cn":"反射强度","en_us":"Reflection strength"},"description":{"zh_cn":"体素反射混进画面的比例，一为原样。","en_us":"How much of the voxel reflection is blended in; one is neutral."},"slider":true}
#define OMNI_VOXEL_REFLECTION_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
体素反射：沿反射方向在体素图上做世界空间追踪，命中方块时用它存下的颜色与光照着色，补上屏幕空间反射看不到的地方。
来源：Eclipse `lib/specular.glsl` 的 `voxelReflection`（选项 `VOXEL_REFLECTIONS_SOLID` 与 `VOXEL_REFLECTIONS_TRANSLUCENT`），
  按本项目结构改写成“一个效果文件”：选项、颜色缓冲的写入与读取、追踪与着色都放在本文件里。
  与原程序的关键差别：原程序把每格六份方块颜色存进一张 SSBO（`lib/specular.glsl` 里的 `voxelSSBO`，原程序已整体注释掉，
  因为每格存六份会让显存占用涨到这张单份图的许多倍）；本项目改用一张自定义三维图像 `omniVoxelColor`，每格只存一份“底色加密光照”。
调用位置：
  一、`rendering/shadow.glsl` 的片元阶段调用 `omniVoxelColorStore`，把地形方块的颜色与光照写进颜色缓冲；
  二、`rendering/composite.glsl` 的合成二号（主世界）经 `effects/reflection/reflection.glsl` 调用 `omniVoxelReflection` 追踪。
  体素编号图（哪一格是哪种方块）仍由 `effects/lighting/lpv.glsl` 在阴影顶点阶段写入，本文件只读它。
可复制示例：
  `omniVoxelColorStore(omniVoxelColorCoord, texel.rgb, blockLight);`      阴影片元写一格颜色
  `vec3 voxelHitWorld; vec4 voxelHit = omniVoxelReflection(worldPos, rayWorldDir, normal, voxelHitWorld);` 追踪，`voxelHit.a >= 0.0` 表示命中
设计原因与取舍：
  一、颜色与光照合存一张八位图：`rgb` 存方块贴图色（已含顶点染色），`a` 存打包的方块光与天光（各占四位）；
      这样反射里的方块既有颜色也有亮度，不必再查一张方块光表。八位精度只用于反射，够用又省显存。
  二、追踪用标准的三维逐格步进（沿射线一格一格走，每步选最近的一根格子边界，撞到实心方块就停）：
      水、冰、玻璃按半透明处理，只给后面的画面染色后继续走，被它们挡住的地形仍会出现在反射里。
  三、彩色水（Eclipse `TRANSLUCENT_IN_REFLECTIONS` 的染色部分）：半透明方块用自己的底色给后面的画面染色，
      水、冰、玻璃的染色强度不同——水最清、玻璃最浓；底色里含生物群系给水的颜色，所以水会按群系偏蓝或偏绿。
  四、铁块镜面（Eclipse `MIRROR_IRON`）：反射撞到铁块时不停止，而是像镜子一样把射线按面法线弹开继续追，
      最多弹 `omniVoxelIronBounces` 次；铁块自己不上色，最终颜色来自弹射后打到的方块。
  五、反射雾：命中时返回真实命中世界坐标，调用方（`effects/reflection/reflection.glsl`）据此算雾段，
      让反射雾、地表散射与雾照明也罩住体素反射，不再是干净的镜面。
  六、默认关闭：关闭时阴影不写颜色、合成不追踪，画面与原来完全一致；只在主世界生效，缺自定义图像能力时不参与编译。
  七、直射光是近似：只按体素面朝太阳的余弦算，不查阴影图，所以阴影里的方块反射会偏亮，属已知近似。
     弹射后的雾段仍按原始反射方向估终点，镜面转角越大偏差越大，同属已知近似。
  八、体素编号图当前只在开启体积光或体素反射时才分配（见 `rendering/pipeline.properties`），
     所以本功能可以单独打开，不必先开体积光。
*/

// 体积坐标、体素编号映射、颜色线性化都来自光传播体积的效果主体，本文件复用同一套约定，避免两套坐标不一致。
#include "/effects/lighting/lpv.glsl"
// 三维逐格步进、半透明染色、镜面弹射与体素着色在通用库。
#include "/gfx/voxel.glsl"

// --- 玩家选项：体素反射开关、追踪距离与强度 ---

// ========================= 写入：阴影片元把方块颜色与光照存进颜色缓冲 =========================
// 只在阴影片元阶段、开启功能且具备自定义图像能力时编译；顶点阶段写编号图，片元阶段才拿得到贴图色。
#if defined(OMNI_FRAGMENT) && defined(OMNI_SHADOW_PASS) && !defined(OMNI_DH_SHADOW_PASS) && !defined(OMNI_END) && !defined(OMNI_NETHER) && OMNI_VOXEL_REFLECTION && defined(IRIS_FEATURE_CUSTOM_IMAGES)
layout(rgba8) uniform restrict image3D omniVoxelColor; // 体素颜色图，阴影片元写、合成只读。
// 写一格：把方块底色与打包光照存进 `omniVoxelColor`；越界不写，下标与体素编号图完全一致。
void omniVoxelColorStore(ivec3 coord, vec3 albedo, vec2 light){
	if (!omniVoxelInside(coord)) return; // 体积外的方块不参与反射，和编号图一样丢弃。
	float blockLevel = floor(saturate(light.x) * 15.0 + 0.5); // 方块光压到四位，零到十五。
	float skyLevel = floor(saturate(light.y) * 15.0 + 0.5); // 天光同样压到四位。
	float packedLight = (blockLevel * 16.0 + skyLevel) / 255.0; // 高四位放方块光、低四位放天光，合成一个通道。
	imageStore(omniVoxelColor, coord, vec4(albedo, packedLight)); // 写入底线颜色与打包光照。
}
#endif // 颜色写入结束。

// ========================= 读取与追踪：合成二号沿反射方向在体素图里逐格前进 =========================
// 只在合成二号的片元阶段、主世界、开启功能且具备自定义图像能力时编译，其余程序整段不参与。
#if defined(OMNI_FRAGMENT) && defined(OMNI_COMPOSITE2_PASS) && !defined(OMNI_NETHER) && !defined(OMNI_END) && OMNI_VOXEL_REFLECTION && defined(IRIS_FEATURE_CUSTOM_IMAGES)
uniform sampler3D omniVoxelColorTex; // 颜色图按采样器读，逐格取色用 texelFetch 保证不插值。
uniform usampler3D omniLpvVoxelTex; // 体素编号图按整数采样器读，用来判断这一格是不是实心。

// 世界空间追踪：从表面沿反射方向在体素图里逐格前进，撞到实心方块就着色返回。
// 参数 `originWorld` 是表面相机相对世界位置，`rayDirWorld` 是世界空间反射方向，`surfaceNormal` 是表面法线；
// 输出参数 `hitWorldPos` 是命中点的相机相对世界位置，供调用方算反射雾段；未命中时它落回起点，调用方不该读。
// 返回值的 `rgb` 是反射颜色，`a` 是归一化总命中距离；`a` 为负表示没有命中，交给调用方走天空回退。
vec4 omniVoxelReflection(vec3 originWorld, vec3 rayDirWorld, vec3 surfaceNormal, out vec3 hitWorldPos){
	vec3 voxelOffset = fract(cameraPosition) + omniLpvHalf; // 相机相对位置到体积坐标的平移。
	return gfx_voxel_reflection(originWorld, rayDirWorld, surfaceNormal, voxelOffset, int(omniLpvSide),
		omniLpvVoxelTex, omniVoxelColorTex, colorTorchlight, colorSkylight, colorShadowlight, worldSunVector,
		float(OMNI_VOXEL_REFLECTION_DISTANCE), OMNI_VOXEL_REFLECTION_STRENGTH, hitWorldPos); // 逐格步进与着色在通用库。
}
#endif // 读取与追踪结束。
#endif // OMNI_EFFECT_REFLECTION_VOXEL_INCLUDED
