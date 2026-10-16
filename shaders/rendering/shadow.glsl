/*
阴影绘制主体：把 iterationT 的阴影顶点与片元两个程序搬进一个主体文件，主世界与远景阴影共用一套代码。
来源：`Lib/Programs/Gbuffers/Shadow_VS.glsl`、`Shadow_FS.glsl` 一比一移植；原程序用 `PROGRAM_DH_SHADOW`
  区分远景阴影，这里换成 `OMNI_SHADOW_PASS` 与 `OMNI_DH_SHADOW_PASS`。
调用位置：各维度 `shadow`、`dh_shadow` 入口定义阶段宏与对应程序宏后引入本文件；入口按 `rendering/programs.json` 生成。
可复制示例：入口写 `#define OMNI_VERTEX 1`、`#define OMNI_SHADOW_PASS 1`、`#define OMNI_OVERWORLD 1`，
  再写 `#include "/rendering/shadow.glsl"`。
输出约定：片元写 `gl_FragData[0]` 阴影颜色与 `gl_FragData[1]` 阴影法线天空光，对应 `DRAWBUFFERS:01`。
设计原因与取舍：
  阴影图是深度写入，顶点负责植物摆动、法线判定与投影压缩，片元写入贴图色与法线天光。
  阴影相关选项、常量与末地阴影相机矩阵都在 `effects/shadow.glsl`，主体引入它；它内部还要 `MaterialMask`
  与时间抗锯齿选项，所以先引入 `effects/material.glsl` 与 `effects/antialiasing.glsl`。
  调用前提（iterationT 与效果文件原样保留）：`effects/shadow.glsl` 的采样函数读取 `worldShadowVector` 与
  `shadowVector`，本节不调用采样函数，仍按它的调用前提给两个空全局。
  注意：`effects/shadow.glsl` 无条件引入 `common/noise.glsl`，其中函数用到只有片元可用的 `gl_FragCoord`，
  顶点阶段引入它会在顶点阶段报错；需要该文件补 `OMNI_FRAGMENT` 守卫，见交付报告存疑项。
*/
#ifndef OMNI_SHADOW_BODY_INCLUDED // 只引入一次，避免选项与常量重复定义。
#define OMNI_SHADOW_BODY_INCLUDED // 置上标记。

// 加载器输入声明，最先引入。
#include "/common/uniforms.glsl"
// 共用纯计算：三次模糊、曲线与法线编解码。
#include "/common/math.glsl"
// 时间抗锯齿选项：`effects/shadow.glsl` 的屏幕空间阴影要用。
#include "/effects/antialiasing.glsl"
// 材质与视差：提供 `MaterialMask`，阴影采样函数要用。
#include "/effects/material.glsl"
// 植物摆动：提供 `WavingPlants` 与阴影摆动开关。
#include "/effects/vegetation.glsl"
// `effects/shadow.glsl` 的采样函数读取这两个方向，本节不调用采样函数，按调用前提给空全局。
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
#include "/effects/shadow.glsl"

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

#ifndef OMNI_DH_SHADOW_PASS
	// 方块实体编号：判定水、冰与植物。
	attribute vec4 mc_Entity;
	#ifdef OMNI_SHADOW_WAVING_PLANTS
		// 方块纹理坐标中点：判断植物哪一半顶点会摆。
		attribute vec4 mc_midTexCoord;
	#endif
#endif

// 实体编号：玩家在阴影里要变黑。
uniform int entityId;


// 顶点主函数：按顺序算摆动、末地矩阵、法线与投影压缩。
void main(){
	color = gl_Color.rgb; // 顶点色取三通道。
	if (entityId == 7003) color.rgb = vec3(0.0); // 玩家自身在阴影里变黑，避免自阴影。
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0); // 纹理坐标。
	vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy; // 原版光照图坐标。
	blockLight = saturate(lmcoord * 1.103449 - 0.0689656); // 重整到零到一。

	vec4 v_viewPos = gl_ModelViewMatrix * gl_Vertex; // 顶点转到阴影相机视空间。

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

	#ifdef OMNI_END // 末地用末地版阴影相机再转一次。
		v_viewPos = shadowModelViewEnd * shadowModelViewInverse * v_viewPos; // 世界坐标重投到末地阴影相机。
	#endif	

	gl_Position = v_viewPos; // 顶点位置放到阴影相机视空间。

	gl_Position.xyz *= vec3(shadowProjection[0][0], shadowProjection[0][0], -shadowProjection[0][0] * 0.5); // 按阴影投影缩放，深度取半。


	vec3 an = abs(gl_Normal); // 法线绝对值。
	tilted = float(max(max(an.x, an.y), an.z) < 0.99); // 三个分量都不到零点九九就是倾斜面。

	#ifdef OMNI_DH_SHADOW_PASS
		normal = gl_Normal; // 远景阴影直接用模型法线。
	#else
		if (mc_Entity.x == 7000.0 || // 闪电。
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


	#ifdef OMNI_END // 末地用末地阴影相机旋转法线。
		normal = normalize(mat3(shadowModelViewEnd) * normal); // 转到末地阴影相机空间。
	#else
		normal = normalize(gl_NormalMatrix * normal); // 转到阴影相机视空间。
	#endif

	float dist = length(gl_Position.xy); // 到阴影图中心的距离。
	float distortFactor = (1.0 - OMNI_SHADOW_MAP_BIAS) + dist * OMNI_SHADOW_MAP_BIAS; // 边缘压缩系数，中心为一。
	gl_Position.xy *= 0.95 / distortFactor; // 向内压缩，边缘分辨率更高。
	

	#ifdef OMNI_DH_SHADOW_PASS
		if (dhMaterialId == DH_BLOCK_WATER) gl_Position.z = 2.0; // 远景水不投阴影，推到最远。
	#else
		if (mc_Entity.x == 8.0 || mc_Entity.x == 79.0) gl_Position.z = 2.0; // 水与冰不投阴影。
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

#ifdef OMNI_DH_SHADOW_PASS
	uniform mat4 shadowProjectionInverse; // 阴影投影的逆矩阵，把像素解回视空间。

	in vec3 viewPos; // 视空间位置。
#endif


// 片元主函数：远景先按距离与朝向剔除，再把贴图色与法线天光写进两张阴影缓冲。
void main(){
	#ifdef OMNI_DH_SHADOW_PASS
		#ifdef OMNI_DH_SHADOW_CULLING // 远景阴影剔除：丢掉被近处挡住、根本看不到的远景块。
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

	#ifdef WHITE_DEBUG_WORLD
		texel.rgb = vec3(1.0); // 调试白光时全白。
	#endif

	if (!gl_FrontFacing && tilted == 0.0) texel.rgb = vec3(0.0); // 背面且不是倾斜面时不算阴影色，避免背面漏色。

	vec3 shadowNormal = normal.xyz; // 阴影法线。

	gl_FragData[0] = texel; // 零号阴影颜色。
	gl_FragData[1] = vec4(shadowNormal.xyz * 0.5 + 0.5, blockLight.y); // 一号阴影法线与天光。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
