/*
覆盖层绘制主体：把 iterationT 的基础、线条、贴图、方块破坏、附魔光、信标光束、天气七组程序合成一个主体文件。
来源：`Lib/Programs/Gbuffers/` 下的 `Basic_VS/FS`、`Line_VS/FS`、`Line_FS_IMAGE`、`Textured_VS/FS`、
  `Damagedblock_VS/FS`、`Armor_Glint_VS/FS`、`Beaconbeam_VS/FS`、`Weather_VS/FS` 一比一移植；原程序靠入口文件
  分别引入，这里用 `OMNI_BASIC_PASS`、`OMNI_LINE_PASS`、`OMNI_TEXTURED_PASS`、`OMNI_DAMAGEDBLOCK_PASS`、
  `OMNI_ARMOR_GLINT_PASS`、`OMNI_BEACONBEAM_PASS`、`OMNI_WEATHER_PASS` 在一个文件里分开。
调用位置：各维度对应的七个 `gbuffers_*` 入口定义阶段宏与各自程序宏后引入本文件；入口按 `rendering/programs.json` 生成。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_WEATHER_PASS 1`、`#define OMNI_OVERWORLD 1`，
  再写 `#include "/rendering/overlay.glsl"`。
输出约定：基础、线条、贴图、信标光束写零号、三号、五号，对应 `DRAWBUFFERS:035`；方块破坏、附魔光、天气只写
  零号，对应 `DRAWBUFFERS:0`；线条开启 `OMNI_LINE_IMAGE_OUTPUT` 时改为图像写入，对应 `DRAWBUFFERS:0`。
设计原因与取舍：
  七组程序彼此独立，只在材质编号、选择框颜色与雨遮罩上共用效果文件；颜色类程序只写零号，表面类程序写完整三张画面。
  天气顶点用风把雨雪几何推斜，片元把雨遮罩乘进零号透明度，都与 iterationT 一致。
  线条图像输出用的扩展声明必须在任何实际代码之前，只能放在文件最上方；选项定义在 `effects/ground/selection.glsl`，
  引入之后才读得到，所以扩展按线条阶段用 `enable` 打开，缺扩展时只警告不报错。
  注意：`effects/weather/weather.glsl` 的 `WeatherRainMask` 含只有片元能用的 `discard`；该函数用 `OMNI_FRAGMENT`
  守卫，顶点阶段整段跳过，所以天气顶点引入本文件不会因 `discard` 而报错。
*/
#ifndef OMNI_OVERLAY_BODY_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_OVERLAY_BODY_INCLUDED // 置上标记。

// 线条图像输出要用图像读写扩展；扩展声明必须在任何实际代码之前，只能放在这里。
#if defined OMNI_LINE_PASS && defined OMNI_FRAGMENT
	#extension GL_ARB_shader_image_load_store : enable
#endif

// 加载器输入声明，最先引入。
#include "/common/uniforms.glsl"
// 共用纯计算：曲线、法线编解码与打包。
#include "/common/math.glsl"
// 时间抗锯齿选项：坐标换算要用它决定是否撤销抖动，必须先于坐标换算引入。
#include "/effects/clarity/antialiasing.glsl"
// 材质与视差：提供 `MATID_*` 与实体法线限制选项。
#include "/effects/ground/material.glsl"
// 选择框：提供 `SelectionBoxColor` 与线条图像输出函数。
#include "/effects/ground/selection.glsl"
// 行星曲率：粒子、线条等覆盖层要与地形实体做同一次下沉，否则远处会浮空，选项与算法都在该文件。
#include "/effects/world/planet.glsl"
// 坐标换算：屏幕、视空间与深度互转，放在 `OMNI_TAA` 定义之后。
#include "/common/coordinates.glsl"

#ifdef OMNI_VERTEX // 顶点阶段：七组程序分开写。
#if defined OMNI_BASIC_PASS || defined OMNI_LINE_PASS // 基础与线条的顶点着色器。
#if defined OMNI_BASIC_PASS
	flat out vec4 color; // 顶点色。
	out vec2 texCoord; // 纹理坐标。
	out vec3 normal; // 视空间法线。
	out vec2 blockLight; // 方块光与天光。
	flat out float isLine; // 是否是线条顶点。
#else
	flat out vec4 color; // 线条只需要顶点色。
#endif

// 线条需要的像素宽常量。
const float LineWidth = 2.5; // 线宽，单位像素。

const float VIEW_SHRINK = 1.0 - (1.0 / 256.0); // 视空间轻微收缩，避免线条端点被裁掉。
const mat4 VIEW_SCALE = mat4( // 视空间收缩矩阵。
	VIEW_SHRINK, 0.0, 0.0, 0.0,
	0.0, VIEW_SHRINK, 0.0, 0.0,
	0.0, 0.0, VIEW_SHRINK, 0.0,
	0.0, 0.0, 0.0, 1.0
);

// 顶点主函数：基础走普通变换，线条把法线当作端点方向撑粗。
void main(){
	#if defined OMNI_BASIC_PASS // 基础几何：常规变换。
		vec4 basicViewPos = gl_ModelViewMatrix * gl_Vertex; // 顶点转到视空间。
		vec3 basicPlanetPos = basicViewPos.xyz; // 复制视空间位置给行星曲率改写。
		omniPlanetCurvatureView(basicPlanetPos); // 行星曲率：基础覆盖层与地形实体同一次下沉，关闭时为零。
		basicViewPos.xyz = basicPlanetPos; // 写回下沉后的视空间位置。
		gl_Position = gl_ProjectionMatrix * basicViewPos; // 投影到裁剪空间，等同原来的 `ftransform`。

		#ifdef OMNI_TAA // 开启时间抗锯齿时给顶点加本帧抖动。
			gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加抖动。
		#endif

		color = gl_Color; // 顶点色。
		texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0); // 纹理坐标。
		normal = gl_NormalMatrix * gl_Normal; // 法线转到视空间。
		vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy; // 原版光照图坐标。
		blockLight = saturate(lmcoord * 1.103449 - 0.0689656); // 重整到零到一。

		isLine = float(clamp(gl_MultiTexCoord1.xy, 0.0, 240.0) != gl_MultiTexCoord1.xy); // 光照图坐标超出范围说明这是线条。
	#else // 线条几何：把线撑到固定像素宽。
		color = gl_Color; // 顶点色。

		vec4 lineViewStart = gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0); // 起点转到视空间。
		vec4 lineViewEnd = gl_ModelViewMatrix * vec4(gl_Vertex.xyz + gl_Normal, 1.0); // 沿法线取终点的视空间位置。
		vec3 lineStartPlanet = lineViewStart.xyz; // 复制起点视空间位置给行星曲率改写。
		vec3 lineEndPlanet = lineViewEnd.xyz; // 复制终点视空间位置给行星曲率改写。
		omniPlanetCurvatureView(lineStartPlanet); // 行星曲率：线条与它框住的方块一起下沉，否则远处会浮在方块上方。
		omniPlanetCurvatureView(lineEndPlanet); // 终点同样下沉，保持线段方向一致。
		lineViewStart.xyz = lineStartPlanet; // 写回下沉后的起点位置。
		lineViewEnd.xyz = lineEndPlanet; // 写回下沉后的终点位置。

		vec4 linePosStart = gl_ProjectionMatrix * VIEW_SCALE * lineViewStart; // 起点投影。
		vec4 linePosEnd = gl_ProjectionMatrix * VIEW_SCALE * lineViewEnd; // 终点同样投影。

		vec3 ndc1 = linePosStart.xyz / linePosStart.w; // 起点转到标准设备坐标。
		vec3 ndc2 = linePosEnd.xyz / linePosEnd.w; // 终点同样转换。

		vec2 lineScreenDirection = normalize((ndc2.xy - ndc1.xy) * screenSize); // 线条在屏幕上的方向。
		vec2 lineOffset = vec2(-lineScreenDirection.y, lineScreenDirection.x) * LineWidth / screenSize; // 垂直方向偏移出线宽。

		lineOffset *= sign(lineOffset.x); // 统一偏移方向，避免两侧不一致。

		if (gl_VertexID % 2 == 0){ // 按顶点序号把两个端点分到线两侧。
			ndc1.xy += lineOffset; // 一侧偏移。
		}else{
			ndc1.xy -= lineOffset; // 另一侧偏移。
		}

		gl_Position = vec4(ndc1 * linePosStart.w, linePosStart.w); // 换回裁剪空间。

		#ifdef OMNI_TAA // 开启时间抗锯齿时给顶点加本帧抖动。
			gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加抖动。
		#endif
	#endif
}
#elif defined OMNI_TEXTURED_PASS || defined OMNI_DAMAGEDBLOCK_PASS || defined OMNI_ARMOR_GLINT_PASS // 贴图、方块破坏、附魔光的顶点着色器。
out vec4 color; // 顶点色。
out vec2 texCoord; // 纹理坐标。
out vec2 blockLight; // 方块光与天光，只有贴图程序用到。

// 顶点主函数：常规变换。
void main(){
	vec4 texturedViewPos = gl_ModelViewMatrix * gl_Vertex; // 顶点转到视空间。
	vec3 texturedPlanetPos = texturedViewPos.xyz; // 复制视空间位置给行星曲率改写。
	omniPlanetCurvatureView(texturedPlanetPos); // 行星曲率：粒子、破坏与附魔光与地形实体同一次下沉，关闭时为零。
	texturedViewPos.xyz = texturedPlanetPos; // 写回下沉后的视空间位置。
	gl_Position = gl_ProjectionMatrix * texturedViewPos; // 投影到裁剪空间，等同原来的 `ftransform`。

	#ifdef OMNI_TAA // 开启时间抗锯齿时给顶点加本帧抖动。
		gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加抖动。
	#endif

	color = gl_Color; // 顶点色。
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0); // 纹理坐标。
	vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy; // 原版光照图坐标。
	blockLight = saturate(lmcoord * 1.103449 - 0.0689656); // 重整到零到一。
}
#elif defined OMNI_BEACONBEAM_PASS // 信标光束顶点着色器。
out vec4 color; // 顶点色。
out vec2 texCoord; // 纹理坐标。
out vec3 viewPos; // 视空间位置。
out vec2 blockLight; // 方块光与天光。

// 顶点主函数：先转到视空间再投影。
void main(){
	vec4 v_viewPos = gl_ModelViewMatrix * gl_Vertex; // 顶点转到视空间。
	vec3 beamPlanetPos = v_viewPos.xyz; // 复制视空间位置给行星曲率改写。
	omniPlanetCurvatureView(beamPlanetPos); // 行星曲率：光束与地形同一次下沉，远处不会浮空。
	v_viewPos.xyz = beamPlanetPos; // 写回下沉后的视空间位置。
	viewPos = v_viewPos.xyz; // 传给片元，用下沉后的位置。
	gl_Position = gl_ProjectionMatrix * v_viewPos; // 投影到裁剪空间。

	#ifdef OMNI_TAA // 开启时间抗锯齿时给顶点加本帧抖动。
		gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加抖动。
	#endif

	color = gl_Color; // 顶点色。
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0); // 纹理坐标。
	vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy; // 原版光照图坐标。
	blockLight = saturate(lmcoord * 1.103449 - 0.0689656); // 重整到零到一。
}
#elif defined OMNI_WEATHER_PASS // 天气顶点着色器。
// 天气风偏移要用的输入：是否露天由加载器算好。

out vec2 texCoord; // 纹理坐标。

// 雨雪风偏移在天气效果文件里，引入它才能读到风向与扰动选项。
#include "/effects/weather/weather.glsl"

// 顶点主函数：按风把雨雪几何推斜后投影。
void main(){
	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex; // 顶点转到视空间。
	vec4 worldPos = gbufferModelViewInverse * viewPos; // 视空间回到相机相对世界坐标。

	vec2 offset = RainWindOffset(worldPos.xyz); // 取雨雪水平偏移，只有露天才推斜。
	worldPos.xz += offset; // 把偏移加到世界坐标横纵轴。

	worldPos.y -= omniPlanetCurvatureDrop(worldPos.xz); // 行星曲率：雨雪与地形同一次下沉，远处才不会悬在半空；关闭时为零。

	gl_Position = gl_ProjectionMatrix * gbufferModelView * worldPos; // 投影到裁剪空间。

	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0); // 纹理坐标。
}
#endif // 顶点程序分支结束。
#endif // 顶点阶段结束。

#if defined OMNI_FRAGMENT && defined OMNI_BASIC_PASS // 基础几何片元着色器。
/* DRAWBUFFERS:035 */
layout(location = 0) out vec4 gbufferOutput0; // 零号贴图色。
layout(location = 1) out vec4 gbufferOutput3; // 三号法线光照图。
layout(location = 2) out vec4 gbufferOutput5; // 五号高光材质。

flat in vec4 color; // 顶点色。
in vec2 texCoord; // 纹理坐标。
in vec3 normal; // 视空间法线。
in vec2 blockLight; // 方块光与天光。
flat in float isLine; // 是否是线条顶点。

// 片元主函数：按透明度丢弃，再把选择框与线条改成固定材质。
void main(){
	vec4 albedo = color; // 底色取顶点色。

	vec2 mcLightmap = blockLight; // 光照图默认取方块光。

	float materialIDs = MATID_LAND; // 默认普通方块。

	#if MC_VERSION >= 11605 // 新版用零点一作为丢弃阈值。
		if (albedo.a < 0.1) discard; // 透明像素丢弃。
	#else
		if (albedo.a <= 0.004) discard; // 旧版阈值更小。
	#endif

	if (albedo.a == 0.4){ // 原程序用零点四标记方块选择框。
		albedo.rgb = SelectionBoxColor(); // 换成配置的选择框颜色。
		materialIDs = MATID_SELECTION; // 记为选择框。
		mcLightmap = vec2(0.0); // 选择框不吃光照图。
	}

	if (isLine > 0.5){ // 线条顶点同样记为选择框。
		materialIDs = MATID_SELECTION; // 记为选择框。
		mcLightmap = vec2(0.0); // 不吃光照图。
	}

	gbufferOutput0 = vec4(albedo.rgb, 1.0); // 零号写不透明底色。
	gbufferOutput3 = vec4(EncodeNormal(normal), mcLightmap); // 三号写法线与光照图。
	gbufferOutput5 = vec4(0.0, 0.0, (materialIDs + 0.1) / 255.0, Pack2x8(vec2(0.0, 1.0))); // 五号只写材质编号，视差阴影记为一。
}
#elif defined OMNI_FRAGMENT && defined OMNI_LINE_PASS // 线条片元着色器。
#if OMNI_LINE_IMAGE_OUTPUT // 图像输出模式：命中像素直接写画面，不写深度。
/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 gbufferOutput0; // 零号，本模式实际不用，只为满足声明。

// 两张图像由 `effects/ground/selection.glsl` 的 `SelectionLineImage` 自己声明并写入。

flat in vec4 color; // 顶点色。

// 片元主函数：命中时把颜色与材质编号写进画面，不写深度。
void main(){
	vec4 albedo = color; // 底色取顶点色。

	if(albedo.a > 0.1 && gl_FragCoord.z < texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x){ // 线条在已有几何前面才写。
		if (albedo.a == 0.4) albedo.rgb = SelectionBoxColor(); // 选择框换成配置颜色。

		SelectionLineImage(albedo); // 把颜色与材质编号写进零号与五号画面。
	}

	discard; // 本模式不通过光栅化输出，全部丢弃。

	gbufferOutput0 = vec4(0.0); // 占位写零，实际走 `discard`。
}
#else // 普通模式：写三张画面。
/* DRAWBUFFERS:035 */
layout(location = 0) out vec4 gbufferOutput0; // 零号贴图色。
layout(location = 1) out vec4 gbufferOutput3; // 三号法线光照图。
layout(location = 2) out vec4 gbufferOutput5; // 五号高光材质。

flat in vec4 color; // 顶点色。

// 片元主函数：线条统一写选择框材质。
void main(){
	vec4 albedo = color; // 底色取顶点色。

	if (albedo.a < 0.1) discard; // 透明像素丢弃。

	if (albedo.a == 0.4) // 原程序用零点四标记方块选择框。
		albedo.rgb = SelectionBoxColor(); // 换成配置的选择框颜色。

	gbufferOutput0 = vec4(albedo.rgb, 1.0); // 零号写不透明底色。
	gbufferOutput3 = vec4(EncodeNormal(vec3(0.0, 0.0, 1.0)), 0.0, 0.0); // 三号写朝外法线与零光照图。
	gbufferOutput5 = vec4(0.0, 0.0, (MATID_SELECTION + 0.1) / 255.0, Pack2x8(vec2(0.0, 1.0))); // 五号写选择框材质编号。
}
#endif // 图像输出与普通模式分支结束。
#endif // 基础与线条片元分支结束。

#if defined OMNI_FRAGMENT && defined OMNI_TEXTURED_PASS // 贴图几何片元着色器。
// 纹理采样器：粒子与受光粒子的贴图。
uniform sampler2D tex; // 贴图。

/* DRAWBUFFERS:035 */
layout(location = 0) out vec4 gbufferOutput0; // 零号贴图色。
layout(location = 1) out vec4 gbufferOutput3; // 三号法线光照图。
layout(location = 2) out vec4 gbufferOutput5; // 五号高光材质。

in vec4 color; // 顶点色。
in vec2 texCoord; // 纹理坐标。
in vec2 blockLight; // 方块光与天光。

// 片元主函数：贴图色乘顶点色，法线朝外，按方块光区分粒子与受光粒子。
void main(){
// 底色：贴图色乘顶点色。
	vec4 albedo = texture(tex, texCoord); // 采贴图。
	albedo *= color; // 乘顶点色。

	if(albedo.a < 0.1) discard; // 透明像素丢弃。

	#ifdef OMNI_WHITE_DEBUG_WORLD
		albedo.rgb = vec3(1.0); // 调试白光时全白。
	#endif


// 法线：粒子面朝外。
	vec2 normalEnc = EncodeNormal(vec3(0.0, 0.0, 1.0)); // 朝外法线。


// 材质编号：方块光接近满值时算受光粒子。
	float materialIDs = MATID_PARTICLE + float(blockLight.x > 0.9999); // 满值并入受光粒子。


	gbufferOutput0 = vec4(albedo.rgb, 1.0); // 零号写不透明底色。
	gbufferOutput3 = vec4(normalEnc, blockLight); // 三号写法线与光照图。
	gbufferOutput5 = vec4(0.0, 0.0, (materialIDs + 0.1) / 255.0, Pack2x8(vec2(0.0, 1.0))); // 五号写材质编号。
}
#endif // 贴图片元结束。

#if defined OMNI_FRAGMENT && defined OMNI_DAMAGEDBLOCK_PASS // 方块破坏叠加片元着色器。
// 纹理采样器：破坏裂纹贴图。
uniform sampler2D tex; // 破坏裂纹贴图。

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 gbufferOutput0; // 零号颜色。

in vec4 color; // 顶点色。
in vec2 texCoord; // 纹理坐标。

// 片元主函数：裂纹贴图乘顶点色，叠加在已破坏方块上。
void main(){
	vec4 albedo = texture(tex, texCoord); // 采裂纹贴图。
	albedo *= color; // 乘顶点色。

	if (albedo.a < 0.1) discard; // 透明像素丢弃。

	#ifdef OMNI_WHITE_DEBUG_WORLD
		albedo.rgb = vec3(1.0); // 调试白光时全白。
	#endif

	gbufferOutput0 = vec4(albedo.rgb, 1.0); // 零号写不透明颜色。
}
#endif // 方块破坏片元结束。

#if defined OMNI_FRAGMENT && defined OMNI_ARMOR_GLINT_PASS // 附魔光片元着色器。
// 纹理采样器：附魔光贴图。
uniform sampler2D tex; // 附魔光贴图。

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 gbufferOutput0; // 零号颜色。

in vec4 color; // 顶点色。
in vec2 texCoord; // 纹理坐标。

// 片元主函数：附魔光保留透明度，由混合方式乘到底层。
void main(){
	vec4 albedo = texture(tex, texCoord); // 采附魔光贴图。
	albedo *= color; // 乘顶点色。

	#ifdef OMNI_WHITE_DEBUG_WORLD
		albedo.rgb = vec3(1.0); // 调试白光时全白。
	#endif

	gbufferOutput0 = albedo; // 零号写附魔光颜色与透明度。
}
#endif // 附魔光片元结束。

#if defined OMNI_FRAGMENT && defined OMNI_BEACONBEAM_PASS // 信标光束片元着色器。
// 纹理采样器：光束贴图、高光与法线。
uniform sampler2D tex; // 光束贴图。
uniform sampler2D specular; // 高光贴图。
uniform sampler2D normals; // 法线贴图。

/* DRAWBUFFERS:035 */
layout(location = 0) out vec4 gbufferOutput0; // 零号贴图色。
layout(location = 1) out vec4 gbufferOutput3; // 三号法线光照图。
layout(location = 2) out vec4 gbufferOutput5; // 五号高光材质。

in vec4 color; // 顶点色。
in vec2 texCoord; // 纹理坐标。
in vec3 viewPos; // 视空间位置。
in vec2 blockLight; // 方块光与天光。

// 片元主函数：光束用面法线造形，高光只取两通道。
void main(){
// 底色：贴图色乘顶点色。
	vec4 albedo = textureLod(tex, texCoord, 0.0); // 采光束贴图。
	albedo *= color; // 乘顶点色。

	#ifdef OMNI_WHITE_DEBUG_WORLD
		albedo.rgb = vec3(1.0); // 调试白光时全白。
	#endif


// 切线基：光束用屏幕导数推出来，只为凑一个坐标系。
	vec2 duv1 = dFdx(texCoord); // 纹理坐标横向屏幕变化。
	vec2 duv2 = dFdy(texCoord); // 纹理坐标纵向屏幕变化。

	vec3 dp1 = dFdx(viewPos); // 视空间位置横向变化。
	vec3 dp2 = dFdy(viewPos); // 视空间位置纵向变化。

	if (albedo.a < 0.122) discard; // 光束边缘丢弃，阈值照原程序。

	mat3 tbn = omniTangentBasis(dp1, dp2, duv1, duv2); // 由已经算好的屏幕导数构造切线基。


// 法线：原程序把法线强制朝外。
	#ifdef MC_NORMAL_MAP
		vec4 materialNormal = omniMaterialNormal(textureLod(normals, texCoord, 0.0).rgb); // 采法线，按选项缩放起伏并解出材质遮蔽。
		vec3 normalTex = materialNormal.xyz; // 缩放后的切线空间法线。
		albedo.rgb *= materialNormal.w; // 材质遮蔽压到底色，未开时为一、不改变画面。
	#else
		vec3 normalTex = vec3(0.0, 0.0, 1.0); // 没有法线贴图时朝外。
	#endif

	normalTex = vec3(0.0, 0.0, 1.0); // 强制朝外，光束本身不显示凹凸。

	vec3 viewNormal = tbn * normalize(normalTex); // 切线空间法线转到视空间。

	#ifdef OMNI_ENTITIES_NORMAL_CLAMP
		vec3 viewDir = -normalize(viewPos); // 视线方向。
		viewNormal = normalize(viewNormal + tbn[2] * inversesqrt(saturate(dot(viewNormal, viewDir)) + 0.001)); // 压住极端法线。
	#endif

	vec2 normalEnc = EncodeNormal(viewNormal); // 八面体编码法线。


// 高光：只取两通道，`PTGI` 编码时自发光放蓝通道。
	#ifdef MC_SPECULAR_MAP
		vec2 specularTex = textureLod(specular, texCoord, 0.0).ba; // 取高光的两通道。
		#if OMNI_TEXTURE_PBR_FORMAT == 2
			specularTex.g = specularTex.r; // `PTGI` 编码把自发光放到第二通道。
		#endif
	#else
		vec2 specularTex = vec2(0.0); // 没有高光贴图时全零。
	#endif


	gbufferOutput0 = vec4(albedo.rgb, 1.0); // 零号写不透明底色。
	gbufferOutput3 = vec4(normalEnc, blockLight); // 三号写法线与光照图。
	gbufferOutput5 = vec4(0.0, Pack2x8(specularTex), (MATID_BEACON_BEAM + 0.1) / 255.0, Pack2x8(vec2(0.0, 1.0))); // 五号写高光与光束材质编号。
}
#endif // 信标光束片元结束。

#if defined OMNI_FRAGMENT && defined OMNI_WEATHER_PASS // 天气片元着色器。
// 纹理采样器：雨雪贴图。
uniform sampler2D tex; // 雨雪贴图。

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 gbufferOutput0; // 零号，只写透明通道作为雨遮罩。

in vec2 texCoord; // 纹理坐标。

// 雨遮罩计算在天气效果文件里，引入它才能读到选项。
#include "/effects/weather/weather.glsl"

// 片元主函数：把雨雪遮罩写进零号透明度，颜色为零，混合方式会把它乘到底层。
void main(){
	vec4 texel = texture(tex, texCoord); // 采雨雪贴图。

	float rainMask = WeatherRainMask(texel); // 取遮罩，空白纹素会被丢弃。

	gbufferOutput0 = vec4(0.0, 0.0, 0.0, rainMask); // 零号只写遮罩到透明度通道。
}
#endif // 天气片元结束。
#endif // 文件守卫结束。
