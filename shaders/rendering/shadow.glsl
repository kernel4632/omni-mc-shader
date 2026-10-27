/*
阴影绘制主体：把 iterationT 的阴影顶点与片元两个程序搬进一个主体文件，主世界与远景阴影共用一套代码。
来源：`Lib/Programs/Gbuffers/Shadow_VS.glsl`、`Shadow_FS.glsl` 一比一移植；原程序用 `PROGRAM_DH_SHADOW`
  区分远景阴影，这里换成 `OMNI_SHADOW_PASS` 与 `OMNI_DH_SHADOW_PASS`。
调用位置：各维度 `shadow`、`dh_shadow` 入口定义阶段宏与对应程序宏后引入本文件；入口按 `rendering/programs.json` 生成。
可复制示例：入口写 `#define OMNI_VERTEX 1`、`#define OMNI_SHADOW_PASS 1`、`#define OMNI_OVERWORLD 1`，
  再写 `#include "/rendering/shadow.glsl"`。
输出约定：片元写 `gl_FragData[0]` 阴影颜色与 `gl_FragData[1]` 阴影法线天空光，共两张阴影缓冲（编号 0 与 1）。
  原程序 `Shadow_FS.glsl` 用 `gl_FragData[0]/[1]` 但不写附件指令（`DRAWBUFFERS`），本文件与其保持一致，同样不写附件指令；
  加载器对阴影程序按固定的两张阴影缓冲绑定，默认写零号与一号。
设计原因与取舍：
  阴影图是深度写入，顶点负责植物摆动、法线判定与投影压缩，片元写入贴图色与法线天光。
  阴影相关选项、常量与末地阴影相机矩阵都在 `effects/shadow/shadow.glsl`，主体引入它；它内部还要 `MaterialMask`
  与时间抗锯齿选项，所以先引入 `effects/ground/material.glsl` 与 `effects/clarity/antialiasing.glsl`。
  调用前提（iterationT 与效果文件原样保留）：`effects/shadow/shadow.glsl` 的采样函数读取 `worldShadowVector` 与
  `shadowVector`，本节不调用采样函数，仍按它的调用前提给两个空全局。
  注意：`effects/shadow/shadow.glsl` 无条件引入 `common/noise.glsl`；该文件用 `OMNI_FRAGMENT` 守卫把 `gl_FragCoord`
  限制在片元阶段（顶点阶段改用常量零），所以阴影顶点引入它不会因缺少片元内建量而报错。
*/
#ifndef OMNI_SHADOW_BODY_INCLUDED // 只引入一次，避免选项与常量重复定义。
#define OMNI_SHADOW_BODY_INCLUDED // 置上标记。

// 加载器输入声明，最先引入。
#include "/common/uniforms.glsl"
// 共用纯计算：三次模糊、曲线与法线编解码。
#include "/common/math.glsl"
// 时间抗锯齿选项：`effects/shadow/shadow.glsl` 的屏幕空间阴影要用。
#include "/effects/clarity/antialiasing.glsl"
// 材质与视差：提供 `MaterialMask`，阴影采样函数要用。
#include "/effects/shared/surface.glsl"
// 植物摆动：提供 `WavingPlants` 与阴影摆动开关。
#include "/effects/ground/vegetation.glsl"
// 行星曲率：阴影顶点要与画面做同一次下沉，选项与算法都在该文件。
#include "/effects/world/planet.glsl"
// `effects/shadow/shadow.glsl` 的采样函数读取这两个方向，本节不调用采样函数，按调用前提给空全局。
vec3 worldShadowVector; // 世界空间阳光方向。
vec3 shadowVector; // 视空间阳光方向。
// 远景阴影依赖加载器在开启远景模组时提供的材质编号；基础环境缺这些名字，按原程序取值补回退。
// 为什么用 `#ifndef`：开启远景模组时由加载器与构建环境注入，重复定义会报错。
#ifndef DISTANT_HORIZONS
	const int dhMaterialId = 0; // 远景材质编号，基础环境当作普通方块。
#endif
#ifndef DH_BLOCK_WATER
	#define DH_BLOCK_WATER 13 // 远景水编号。
#endif
// 阴影：提供全部阴影选项、`shadowDistance`、`shadowMapResolution` 与末地阴影相机矩阵。
#include "/effects/shared/shadow.glsl"
// 末地主岛光源：提供选项与主岛阴影相机矩阵，末地阴影顶点在开启它时改用这套竖直向下的相机投几何。
#include "/effects/world/end_island_light.glsl"
// 光传播体积：提供体素编号映射与写体素图的函数，选项关闭或缺能力时整段不编译。
#include "/effects/shared/lpv.glsl"
// 体素反射：提供把方块底色写进体素颜色图的函数，选项关闭或缺能力时整段不编译；它复用上面的体积坐标。
#include "/effects/reflection/voxel.glsl"
#ifdef OMNI_FRAGMENT
	// 远景阴影淡入要用的 `DHShadowChunkFading`；它用到片元专用的 `discard` 与蓝噪声，所以只在片元阶段引入。
	#include "/effects/world/world.glsl"
#endif

#ifdef OMNI_VERTEX // 顶点阶段：阴影顶点着色器。
// 传给片元的插值量。
out vec2 texCoord; // 纹理坐标。
out vec3 color; // 顶点色。
out vec3 normal; // 视空间法线。
out vec2 blockLight; // 方块光与天光。
out float tilted; // 是否是倾斜面，用来判断背面丢弃。
#ifdef OMNI_DH_SHADOW_PASS
	out vec3 viewPos; // 远景阴影要带视空间位置做剔除。
#endif
#if OMNI_VOXEL_REFLECTION && defined(IRIS_FEATURE_CUSTOM_IMAGES)
	flat out ivec3 omniVoxelColorCoord; // 这个顶点所属体素格的坐标，交给片元写颜色缓冲。
	flat out float omniVoxelColorWrite; // 是否要写颜色缓冲；非地形与远景阴影保持零，片元据此跳过。
#endif

#ifndef OMNI_DH_SHADOW_PASS
	// 方块实体编号：判定水、冰与植物。
	attribute vec4 mc_Entity;
	#ifdef OMNI_SHADOW_WAVING_PLANTS
		// 方块纹理坐标中点：判断植物哪一半顶点会摆。
		attribute vec4 mc_midTexCoord;
	#endif
	#if (OMNI_LPV_ENABLED || OMNI_VOXEL_REFLECTION) && defined IRIS_FEATURE_CUSTOM_IMAGES
		// 方块中心相对顶点的偏移：把火把、花这类小模型对齐到正确的整格，体素才填得准；体积光与体素反射都要它。
		attribute vec3 at_midBlock;
	#endif
#endif

// 实体编号：玩家在阴影里要变黑。
uniform int entityId;
// 当前几何的原版绘制阶段，取值与 Iris 的 `MC_RENDER_STAGE_*` 对应；体积光靠它区分地形、方块实体与实体。
uniform int renderStage;
// 方块实体编号：按 `block.properties` 映射，供体积光把发光方块实体当光源。
uniform int blockEntityId;
// 当前渲染的物品编号：方块物品按 `block.properties` 映射、其它物品按 `item.properties` 映射，供体积光把掉落物当光源。
uniform int currentRenderedItemId;


// 顶点主函数：按顺序算摆动、末地矩阵、法线与投影压缩。
void main(){
	color = gl_Color.rgb; // 顶点色取三通道。
	if (entityId == 7003) color.rgb = vec3(0.0); // 玩家自身在阴影里变黑，避免自阴影。
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0); // 纹理坐标。
	vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy; // 原版光照图坐标。
	blockLight = saturate(lmcoord * 1.103449 - 0.0689656); // 重整到零到一。

	vec4 v_viewPos = gl_ModelViewMatrix * gl_Vertex; // 顶点转到阴影相机视空间。

	#if OMNI_VOXEL_REFLECTION && defined(IRIS_FEATURE_CUSTOM_IMAGES)
		omniVoxelColorCoord = ivec3(0); // 默认不写颜色；远景阴影与末地没有体素反射，保持零即可。
		omniVoxelColorWrite = 0.0; // 默认关闭颜色写入，只有地形才打开。
	#endif

	#if (OMNI_LPV_ENABLED || OMNI_VOXEL_REFLECTION) && defined IRIS_FEATURE_CUSTOM_IMAGES
	#if !defined OMNI_DH_SHADOW_PASS && !defined OMNI_END
		#ifdef OMNI_LPV_ENTITY_LIGHTS
		if (renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES){
			// 方块实体光源：只给信标、潮涌核心、附魔台、酿造台、末地传送门这些发光方块实体写体素，让它们点亮体积光；
			// 其它方块实体不写，避免把信标光束这类大体积几何误写成挡光格子。
			uint blockEntityVoxel = omniLpvBlockEntityVoxelId(blockEntityId); // 方块实体编号映射成体素编号，非光源得到零。
			if (blockEntityVoxel > 0u){
				vec3 voxelPos = (shadowModelViewInverse * v_viewPos).xyz; // 方块实体顶点直接换成相机相对世界坐标，不加方块中心偏移。
				omniVoxelStore(omniVoxelIndex(voxelPos), blockEntityVoxel); // 写进体素图，越界自动丢弃。
			}
		}
		else
		#endif
		// 光传播体积：地形写体素；顶点代表方块的一个角，加上方块中心偏移后落到该方块所属的整格，整块六个面写到同一格。
		if (entityId == 0){
			vec3 voxelPos = (shadowModelViewInverse * v_viewPos).xyz + at_midBlock / 64.0; // 相机相对世界位置加中心偏移。
			omniVoxelStore(omniVoxelIndex(voxelPos), omniVoxelBlockId(mc_Entity.x)); // 写进体素图，越界自动丢弃。
			#if OMNI_VOXEL_REFLECTION
				omniVoxelColorCoord = omniVoxelIndex(voxelPos); // 记下体素坐标，片元用采样到的贴图色写这一格。
				omniVoxelColorWrite = 1.0; // 标记这一格要写颜色。
			#endif
		}
		#ifdef OMNI_LPV_ENTITY_LIGHTS
		else {
			// 实体与掉落物光源：先给发光实体写体素，再给掉落的发光物品写体素；都不发光就跳过，光正常穿过它们。
			uint entityVoxel = omniLpvEntityVoxelId(entityId); // 把实体编号映射成体素编号，非发光实体得到零。
			if (entityVoxel == 0u) entityVoxel = omniLpvDroppedItemVoxelId(currentRenderedItemId); // 不是发光实体再看它是不是发光的掉落物品。
			if (entityVoxel > 0u){
				vec3 voxelPos = (shadowModelViewInverse * v_viewPos).xyz; // 实体顶点直接换成相机相对世界坐标，不加方块中心偏移。
				omniVoxelStore(omniVoxelIndex(voxelPos), entityVoxel); // 写进体素图；同一实体的多个顶点会重复写同一格，结果一致。
			}
		}
		#endif
	#endif
	#endif

	#ifdef OMNI_DH_SHADOW_PASS
		viewPos = v_viewPos.xyz; // 远景阴影记下视空间位置。
	#endif

	#ifdef OMNI_SHADOW_WAVING_PLANTS // 阴影里的植物也摆，且只有非远景、非末地才有。
	#if !defined OMNI_DH_SHADOW_PASS && !defined OMNI_END
		vec4 worldPos = shadowModelViewInverse * v_viewPos; // 阴影视空间回到世界坐标。
		worldPos.xyz += cameraPosition; // 加上相机绝对位置。

		WavingPlants(worldPos.xyz, mc_Entity.x, blockLight.y, gl_MultiTexCoord0.y, mc_midTexCoord.y); // 与地形共用同一套摆动，摆动开关由它自己判断。

		worldPos.xyz -= cameraPosition; // 减回相机相对世界坐标。
		v_viewPos = shadowModelView * worldPos; // 再投回阴影相机视空间。
	#endif
	#endif

	// 行星曲率：阴影顶点必须与画面里的地形实体做同一次下沉，否则阴影会留在原来的高度而与几何错位。
	// 阴影相机视空间与相机视空间原点相同、朝向不同，所以按阴影相机矩阵转回相机相对世界坐标再下沉；
	// 与地形实体共用同一份公式，摆放顺序也一致（先摆动、再下沉），保证阴影下的形状和本体完全对齐。
	vec3 curvedShadowViewPos = v_viewPos.xyz; // 复制阴影相机视空间位置。
	omniPlanetCurvatureView(curvedShadowViewPos, mat3(shadowModelViewInverse), mat3(shadowModelView)); // 用阴影相机矩阵做同一次下沉。
	v_viewPos.xyz = curvedShadowViewPos; // 写回下沉后的位置。

	#ifdef OMNI_END // 末地的阴影图不用加载器给的阴影相机，单独投一次。
		#ifdef OMNI_END_ISLAND_LIGHT // 开启主岛光源时改用竖直向下的主岛阴影相机（照 Eclipse），这样光照与阴影方向一致。
			vec3 endLightWorldPos = (shadowModelViewInverse * v_viewPos).xyz; // 视空间换回相机相对世界坐标。
			gl_Position = endLightShadowProjection * endLightShadowModelView * vec4(endLightWorldPos, 1.0); // 直接给裁剪坐标，透视除法交给硬件。
		#else // 关闭时保持原来的末地太阳阴影相机。
			v_viewPos = shadowModelViewEnd * shadowModelViewInverse * v_viewPos; // 世界坐标重投到末地阴影相机。
			gl_Position = v_viewPos; // 顶点位置放到阴影相机视空间。
			gl_Position.xyz *= vec3(shadowProjection[0][0], shadowProjection[0][0], -shadowProjection[0][0] * 0.5); // 按阴影投影缩放，深度取半。
		#endif
	#else // 主世界与下界用加载器给的阴影相机。
		gl_Position = v_viewPos; // 顶点位置放到阴影相机视空间。
		gl_Position.xyz *= vec3(shadowProjection[0][0], shadowProjection[0][0], -shadowProjection[0][0] * 0.5); // 按阴影投影缩放，深度取半。
	#endif


	vec3 an = abs(gl_Normal); // 法线绝对值。
	tilted = float(max(max(an.x, an.y), an.z) < 0.99); // 三个分量都不到零点九九就是倾斜面。

	#ifdef OMNI_DH_SHADOW_PASS
		normal = gl_Normal; // 远景阴影直接用模型法线。
	#else
		if (mc_Entity.x == 7000.0 || // 闪电。
			mc_Entity.x == 12.0 || // 单独的矮草。
			mc_Entity.x == 7010.0 || // 一种草。
			mc_Entity.x == 7011.0 || // 小麦。
			mc_Entity.x == 7020.0 || // 一种双层草。
			mc_Entity.x == 7021.0 || // 另一种双层草。
			mc_Entity.x == 7040.0){ // 又一类植物。
			
			normal = vec3(0.0, 1.0, 0.0); // 植物法线当作朝上。
			tilted = 1.0; // 植物按倾斜面处理。
		}else{
			normal = gl_Normal; // 其余用模型法线。
		}
	#endif


	#ifdef OMNI_END // 末地的法线跟着阴影相机走。
		#ifdef OMNI_END_ISLAND_LIGHT // 主岛阴影相机是常量旋转，取它的旋转部分即可。
			normal = normalize(mat3(endLightShadowModelView) * normal); // 转到主岛阴影相机空间。
		#else
			normal = normalize(mat3(shadowModelViewEnd) * normal); // 转到末地阴影相机空间。
		#endif
	#else
		normal = normalize(gl_NormalMatrix * normal); // 转到阴影相机视空间。
	#endif

	#if defined OMNI_END && defined OMNI_END_ISLAND_LIGHT // 主岛阴影相机是透视投影，不做正交的边缘压缩。
		#ifdef OMNI_DH_SHADOW_PASS
			if (dhMaterialId == DH_BLOCK_WATER) gl_Position.z = gl_Position.w; // 远景水不投阴影，推到远裁剪面。
		#else
			if (mc_Entity.x == 8.0 || mc_Entity.x == 79.0) gl_Position.z = gl_Position.w; // 水与冰不投阴影，推到远裁剪面。
		#endif
	#else // 其余相机都是正交投影，按原程序做边缘压缩与深度处理。
		float dist = length(gl_Position.xy); // 到阴影图中心的距离。
		float distortFactor = (1.0 - OMNI_SHADOW_MAP_BIAS) + dist * OMNI_SHADOW_MAP_BIAS; // 边缘压缩系数，中心为一。
		gl_Position.xy *= 0.95 / distortFactor; // 向内压缩，边缘分辨率更高。

		#ifdef OMNI_DH_SHADOW_PASS
			if (dhMaterialId == DH_BLOCK_WATER) gl_Position.z = 2.0; // 远景水不投阴影，推到最远。
		#else
			if (mc_Entity.x == 8.0 || mc_Entity.x == 79.0) gl_Position.z = 2.0; // 水与冰不投阴影。
		#endif
	#endif
}
#endif // 顶点阶段结束。

#ifdef OMNI_FRAGMENT // 片元阶段：阴影片元着色器。
// 纹理采样器：贴图色。
uniform sampler2D tex; // 方块或实体的贴图。

// 从顶点阶段接收的插值量。
in vec2 texCoord; // 纹理坐标。
in vec3 color; // 顶点色。
in vec3 normal; // 视空间法线。
in vec2 blockLight; // 方块光与天光。
in float tilted; // 是否是倾斜面。

#if OMNI_VOXEL_REFLECTION && defined(IRIS_FEATURE_CUSTOM_IMAGES)
	flat in ivec3 omniVoxelColorCoord; // 顶点算出的体素坐标，用来定位要写颜色的那一格。
	flat in float omniVoxelColorWrite; // 顶点标记是否要写颜色，非地形为零。
#endif

#ifdef OMNI_DH_SHADOW_PASS
	uniform mat4 shadowProjectionInverse; // 阴影投影的逆矩阵，把像素解回视空间。

	in vec3 viewPos; // 视空间位置。
#endif


// 片元主函数：远景先按距离与朝向剔除，再把贴图色与法线天光写进两张阴影缓冲。
void main(){
	#ifdef OMNI_DH_SHADOW_PASS
		#if OMNI_DH_SHADOW_CULLING // 远景阴影剔除：丢掉被近处挡住、根本看不到的远景块。
			vec3 viewPosOrigin = viewPos; // 复制一份视空间位置。
			viewPosOrigin.z += 100.0; // 沿视线方向前推一百格，变成远处的参考点。
			#ifdef OMNI_END		
				vec3 worldPosInterval = mat3(shadowModelViewInverseEnd) * viewPosOrigin; // 末地用末地逆矩阵转回世界。
			#else
				vec3 worldPosInterval = mat3(shadowModelViewInverse) * viewPosOrigin; // 其它维度用加载器逆矩阵。
			#endif

			vec2 worldDist = vec2(length(worldPosInterval.xz), worldPosInterval.y); // 水平距离与高度。

			float clipDist = min(shadowDistance, far) * 0.7; // 剔除半径取阴影距离与远裁剪面的较小者的七成。
			#ifdef OMNI_DH_SHADOW_FIX
				if (worldDist.x < clipDist && worldDist.y > -clipDist || normal.z <= 0.0) discard; // 修正开关额外丢掉背光面。
			#else
				if (worldDist.x < clipDist && worldDist.y > -clipDist) discard; // 半径内的远景块丢掉。
			#endif
		#else
			#ifdef OMNI_DH_SHADOW_FIX
				if (normal.z <= 0.0) discard; // 只按朝向剔除背光面。
			#endif
		#endif

		// 远景阴影淡入：远景阴影靠近阴影距离边界时按随机阈值淡出，避免阴影图边缘出现硬边。
		// 距离取阴影视空间的长度，是到阴影相机（近似到玩家）的距离，属按距离的近似；二档才生效。
		#if OMNI_DH_CHUNK_FADING > 1
			DHShadowChunkFading(length(viewPos), min(shadowDistance, far)); // 按距离与阴影距离边界随机淡出。
		#endif

		#ifdef OMNI_DH_SHADOW_FIX
			vec2 currNdcPos = gl_FragCoord.xy / float(shadowMapResolution) * 2.0 - 1.0; // 当前像素转到负一到一。
			currNdcPos *= (1.0 - OMNI_SHADOW_MAP_BIAS) / (0.95 - length(currNdcPos) * OMNI_SHADOW_MAP_BIAS); // 与写入端同口径反向解压缩。
			vec2 currViewPos = currNdcPos * vec2(shadowProjectionInverse[0][0], shadowProjectionInverse[0][0]); // 换回视空间横纵。

			float z = viewPos.z; // 从视空间深度起算。

			z += dot(viewPos.xy - currViewPos, normal.xy) / normal.z; // 沿当前面把深度推到该像素的实际高度。
				
			gl_FragDepth = 0.5 - z * shadowProjection[0][0] * 0.25; // 直接写深度，修掉颗粒状伪影。
		#endif
	#endif

	vec4 texel = textureLod(tex, texCoord, 0.0); // 采贴图。
	texel.rgb *= color; // 乘顶点色。

	#ifdef OMNI_WHITE_DEBUG_WORLD
		texel.rgb = vec3(1.0); // 调试白光时全白。
	#endif

	if (!gl_FrontFacing && tilted == 0.0) texel.rgb = vec3(0.0); // 背面且不是倾斜面时不算阴影色，避免背面漏色。

	vec3 shadowNormal = normal.xyz; // 阴影法线。

	#if OMNI_VOXEL_REFLECTION && !defined(OMNI_DH_SHADOW_PASS) && !defined(OMNI_END) && !defined(OMNI_NETHER) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
		if (omniVoxelColorWrite > 0.5) omniVoxelColorStore(omniVoxelColorCoord, texel.rgb, blockLight); // 把这一格的底色与光照写进体素颜色图。
	#endif

	gl_FragData[0] = texel; // 零号阴影颜色。
	gl_FragData[1] = vec4(shadowNormal.xyz * 0.5 + 0.5, blockLight.y); // 一号阴影法线与天光。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
