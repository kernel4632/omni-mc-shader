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
#ifndef OMNI_VOXEL_REFLECTION_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_VOXEL_REFLECTION_INCLUDED // 置上标记，后续再次引用直接跳过。

// 体积坐标、体素编号映射、颜色线性化都来自光传播体积的效果主体，本文件复用同一套约定，避免两套坐标不一致。
#include "/effects/lighting/lpv.glsl"

// --- 玩家选项：体素反射开关、追踪距离与强度 ---
// @effect {"label":{"zh_cn":"体素反射","en_us":"Voxel reflections"}}
// @option {"label":{"zh_cn":"体素反射","en_us":"Voxel reflections"},"description":{"zh_cn":"在体素图上追踪反射，屏幕空间反射没命中的地方用体素里的方块颜色补上；只在主世界生效，缺自定义图像能力时不参与编译，关闭时画面不变。","en_us":"Traces reflections through the voxel grid and fills screen-space misses with stored block colours; overworld only, off keeps the picture unchanged."}}
//#define OMNI_VOXEL_REFLECTION
// @option {"label":{"zh_cn":"追踪距离","en_us":"Trace distance"},"description":{"zh_cn":"体素反射最远能打多远，越大越能反射远处地形，也更慢。","en_us":"How far voxel reflections reach; larger reflects more distant terrain but is slower."},"slider":true}
#define OMNI_VOXEL_REFLECTION_DISTANCE 64 // [32 48 64 96]
// @option {"label":{"zh_cn":"反射强度","en_us":"Reflection strength"},"description":{"zh_cn":"体素反射混进画面的比例，一为原样。","en_us":"How much of the voxel reflection is blended in; one is neutral."},"slider":true}
#define OMNI_VOXEL_REFLECTION_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]

// ========================= 写入：阴影片元把方块颜色与光照存进颜色缓冲 =========================
// 只在阴影片元阶段、开启功能且具备自定义图像能力时编译；顶点阶段写编号图，片元阶段才拿得到贴图色。
#if defined(OMNI_FRAGMENT) && defined(OMNI_SHADOW_PASS) && !defined(OMNI_DH_SHADOW_PASS) && !defined(OMNI_END) && !defined(OMNI_NETHER) && defined(OMNI_VOXEL_REFLECTION) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
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
#if defined(OMNI_FRAGMENT) && defined(OMNI_COMPOSITE2_PASS) && !defined(OMNI_NETHER) && !defined(OMNI_END) && defined(OMNI_VOXEL_REFLECTION) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
uniform sampler3D omniVoxelColorTex; // 颜色图按采样器读，逐格取色用 texelFetch 保证不插值。
uniform usampler3D omniLpvVoxelTex; // 体素编号图按整数采样器读，用来判断这一格是不是实心。

const int omniVoxelMaxSteps = 320; // 每根射线最多走的格数，覆盖整条体积对角线还有余量。
const int omniVoxelIronBounces = 4; // 铁块镜面最多弹射几次，防止两面镜子互相反射把循环拖满。

// 半透明方块：水、冰、玻璃，光线穿过后只给后面的画面染色，不停下。
bool omniVoxelIsTranslucent(uint id){ return id == 8u || id == 79u || id == 95u; }
// 植物：草、花、树叶等，不挡光也不算实体，直接穿过。
bool omniVoxelIsPlant(uint id){ return id == 12u || id == 7000u || id == 7010u || id == 7011u || id == 7020u || id == 7021u || id == 7030u || id == 7040u; }
// 铁块：反射撞到它时当镜子处理；编号 504 与 `block.properties` 的 `block.504` 一致，改一处要同步改两处。
bool omniVoxelIsIron(uint id){ return id == 504u; }

// 半透明方块的染色强度：水最清、冰居中、玻璃最浓，来源 Eclipse `TRANSLUCENT_IN_REFLECTIONS` 里按透明度决定染色比例的做法。
// 为什么按编号分档：这个八位颜色图没有存方块的透明度，只能按方块种类近似；玻璃本身有色，染色就重一些。
float omniVoxelTintStrength(uint id){
	if (id == 8u) return 0.4; // 水：多数是清水，只带一点生物群系颜色。
	if (id == 79u) return 0.6; // 冰：本身偏蓝。
	return 0.8; // 玻璃与染色玻璃：颜色最重。
}
// 算一层半透明染色：把方块底色归一化成方向色（保留色相、去掉亮度），再按强度与无色混合。
// 为什么归一化：只用色相给后面的画面染色，避免水太亮把反射整个提白。
vec3 omniVoxelTranslucentTint(uint id, vec3 albedo){
	return mix(vec3(1.0), omniNormalize(albedo), omniVoxelTintStrength(id));
}

// 给命中的体素面上色：底色乘（方块光加天光的间接光，再加直射太阳光）。
// 参数 `packedLight` 是写入端打包的方块光与天光，`voxelNormal` 是进入面朝外的法线。
vec3 omniVoxelShade(vec3 albedo, vec3 voxelNormal, float packedLight){
	float packed = floor(packedLight * 255.0 + 0.5); // 还原成整数位的打包光照。
	float blockLevel = floor(packed / 16.0) / 15.0; // 高四位是方块光等级。
	float skyLevel = mod(packed, 16.0) / 15.0; // 低四位是天光等级。
	vec3 indirect = colorTorchlight * blockLevel + colorSkylight * skyLevel; // 方块光与天光一起给环境亮度。
	vec3 direct = colorShadowlight * saturate(dot(voxelNormal, worldSunVector)); // 直射按体素面朝太阳的余弦。
	return albedo * (indirect + direct) * OMNI_VOXEL_REFLECTION_STRENGTH; // 底色乘光照与玩家强度。
}

// 世界空间追踪：从表面沿反射方向在体素图里逐格前进，撞到实心方块就着色返回。
// 参数 `originWorld` 是表面相机相对世界位置，`rayDirWorld` 是世界空间反射方向，`surfaceNormal` 是表面法线；
// 输出参数 `hitWorldPos` 是命中点的相机相对世界位置，供调用方算反射雾段；未命中时它落回起点，调用方不该读。
// 返回值的 `rgb` 是反射颜色，`a` 是归一化总命中距离；`a` 为负表示没有命中，交给调用方走天空回退。
// 为什么拆内外两层循环：外层负责铁块镜面弹射，每弹一次就把起点、方向、逐格步进状态整组重设；
// 内层就是原来那条从起点到命中或到边界的直线步进，逻辑与没有镜面时完全一样。
vec4 omniVoxelReflection(vec3 originWorld, vec3 rayDirWorld, vec3 surfaceNormal, out vec3 hitWorldPos){
	hitWorldPos = originWorld; // 先给一个占位，命中时才被真正赋值。

	if (dot(rayDirWorld, surfaceNormal) <= 0.0) return vec4(0.0, 0.0, 0.0, -1.0); // 射线朝表面内侧，追踪没有意义。

	float maxDist = min(float(OMNI_VOXEL_REFLECTION_DISTANCE), float(omniLpvSide)); // 追踪距离不超过体积边长。
	vec3 accumTint = vec3(1.0); // 半透明方块累积的染色，最后乘到后面的画面上。
	float traveled = 0.0; // 已经走过的米数，跨镜面弹射累加，用来对总距离封顶。

	vec3 posWorld = originWorld + surfaceNormal * 0.05; // 起点沿法线抬起一点，避开表面自身那一格。
	vec3 dir = rayDirWorld; // 当前这段射线的方向，铁块弹射后会被改掉。

	for (int bounce = 0; bounce <= omniVoxelIronBounces; bounce++){ // 每多弹一次镜面就多跑一段直线步进。

		vec3 gridPos = omniLpvPosition(posWorld); // 转成体素网格坐标，整数边界就是体素边界。
		ivec3 cell = ivec3(floor(gridPos)); // 起点所在体素下标。
		if (!omniVoxelInside(cell)) return vec4(0.0, 0.0, 0.0, -1.0); // 起点不在体积内，无法追踪。

		ivec3 stepDir = ivec3(sign(dir)); // 每轴前进方向，正负一或零。
		vec3 invDir = 1.0 / dir; // 方向倒数，用来算跨边界的参数距离。
		vec3 tDelta = abs(invDir); // 跨过一整格所需的参数距离。
		vec3 tMax = vec3(1e30); // 到下一个边界的参数距离；方向为零的轴保持极大值，不会被先选中。
		if (dir.x != 0.0) tMax.x = (float(cell.x) + max(sign(dir.x), 0.0) - gridPos.x) * invDir.x;
		if (dir.y != 0.0) tMax.y = (float(cell.y) + max(sign(dir.y), 0.0) - gridPos.y) * invDir.y;
		if (dir.z != 0.0) tMax.z = (float(cell.z) + max(sign(dir.z), 0.0) - gridPos.z) * invDir.z;

		bool mirrored = false; // 这一段是否以击中铁块镜面结束。
		for (int i = 0; i < omniVoxelMaxSteps; i++){
			float tMin = min(min(tMax.x, tMax.y), tMax.z); // 最近的一次跨格距离。
			if (traveled + tMin > maxDist) return vec4(0.0, 0.0, 0.0, -1.0); // 总距离超出上限，没有命中。

			vec3 faceNormal = vec3(0.0); // 本次进入体素的朝向；沿哪个轴走就从它的对面进入。
			if (tMax.x <= tMin){ cell.x += stepDir.x; tMax.x += tDelta.x; faceNormal.x = -float(stepDir.x); } // 走横轴这一格。
			else if (tMax.y <= tMin){ cell.y += stepDir.y; tMax.y += tDelta.y; faceNormal.y = -float(stepDir.y); } // 走纵轴这一格。
			else { cell.z += stepDir.z; tMax.z += tDelta.z; faceNormal.z = -float(stepDir.z); } // 走深度轴这一格。

			if (!omniVoxelInside(cell)) return vec4(0.0, 0.0, 0.0, -1.0); // 走出体积，后面的格子没有编号。

			uint voxelId = texelFetch(omniLpvVoxelTex, cell, 0).r; // 读这一格的方块编号。
			if (voxelId == 0u) continue; // 空气，继续走。
			if (omniVoxelIsPlant(voxelId)) continue; // 植物不挡光，继续走。

			vec4 stored = texelFetch(omniVoxelColorTex, cell, 0); // 读这一格的颜色与光照。
			vec3 albedo = omniSrgbToLinear(stored.rgb); // 贴图色从 sRGB 换回线性，与场景单位一致。
			if (omniVoxelIsTranslucent(voxelId)){ accumTint *= omniVoxelTranslucentTint(voxelId, albedo); continue; } // 水冰玻璃按彩色水染色后继续。

			vec3 hitPoint = posWorld + dir * tMin; // 本次刚跨进来的边界点，就是命中面所在位置。

			if (omniVoxelIsIron(voxelId) && bounce < omniVoxelIronBounces){ // 铁块镜面：弹开再追，铁块自己不上色。
				traveled += tMin; // 把这一段长度计入总距离。
				hitWorldPos = hitPoint; // 先记住镜面位置，后续万一没命中仍有合理取值。
				posWorld = hitPoint + faceNormal * 0.01; // 起点抬离镜面，避免下一次步进又落回同一格。
				dir = reflect(dir, faceNormal); // 按进入面法线弹射。
				mirrored = true; // 标记本段以镜面结束，去跑下一段。
				break; // 退出内层，外层用新的起点与方向重设步进状态。
			}

			hitWorldPos = hitPoint; // 命中点的相机相对世界位置，调用方用它算雾段。
			vec3 shaded = omniVoxelShade(albedo, faceNormal, stored.a) * accumTint; // 按体素面法线着色并乘上半透明染色。
			return vec4(shaded, saturate((traveled + tMin) / maxDist)); // 归一化总命中距离放进 a，供反射滤波使用。
		}

		if (!mirrored) return vec4(0.0, 0.0, 0.0, -1.0); // 走到步数上限还没命中，交给调用方走天空回退。
	}

	return vec4(0.0, 0.0, 0.0, -1.0); // 镜面弹射次数用尽仍未命中，交给调用方走天空回退。
}
#endif // 读取与追踪结束。
#endif // 文件守卫结束。
