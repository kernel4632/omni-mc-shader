/*
天体绘制主体：把 iterationT 的天空基础与天空贴图三阶段程序合成一个主体文件。
来源：`Lib/Programs/Gbuffers/Skybasic_VS.glsl`、`Skybasic_FS.glsl`、`Skytextured_VS.glsl`、`Skytextured_GS.glsl`、
  `Skytextured_FS.glsl` 一比一移植；原程序用入口文件选择，这里用 `OMNI_SKYBASIC_PASS` 与 `OMNI_SKYTEXTURED_PASS`
  在一个文件里分开。
调用位置：各维度 `gbuffers_skybasic`、`gbuffers_skytextured` 入口定义阶段宏与对应程序宏后引入本文件；
  入口按 `rendering/programs.json` 生成，只有主世界的天空贴图带几何阶段。
可复制示例：入口写 `#define OMNI_GEOMETRY 1`、`#define OMNI_SKYTEXTURED_PASS 1`、`#define OMNI_OVERWORLD 1`，
  再写 `#include "/rendering/celestial.glsl"`。
输出约定：只写零号，对应 `DRAWBUFFERS:0`，`deferred3` 把它当天体颜色读取。
设计原因与取舍：
  天空基础画原版天空渐变，天空贴图画日月与天空盒贴图，两者都靠叠加混合进零号画面。
  日月与天空盒的开关选项归属 `effects/sky/sky.glsl`，只在片元引入它；顶点与几何阶段只用时间抗锯齿选项。
  `effects/sky/sky.glsl` 的星点函数读取世界太阳方向，引入前要给它一个空全局，几何阶段不引入它所以不需要。
  资源包天空（`OMNI_RESOURCEPACK_SKY`，只主世界）打开时天空基础与天空贴图照画全部原版绘制阶段，
  让资源包的自定义天空层、日月与星空原样叠进零号画面，供延迟三号当天空底色读；关闭或非主世界时维持原来的丢弃规则。
*/
#ifndef OMNI_CELESTIAL_BODY_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_CELESTIAL_BODY_INCLUDED // 置上标记。

// 加载器输入声明，最先引入。
#include "/common/uniforms.glsl"
// 共用纯计算。
#include "/common/math.glsl"
// 时间抗锯齿选项：顶点抖动要用。
#include "/effects/clarity/antialiasing.glsl"
// 天空选项归属文件，只在片元引入；它的星点函数读取世界太阳方向，先给一个空全局满足调用前提。
#ifdef OMNI_FRAGMENT
	// `effects/sky/sky.glsl` 的星点函数读取世界太阳方向，几何阶段不用，这里给一个空全局。
	vec3 worldSunVector;
	// 天空：提供日月贴图与天空盒贴图、星点类型的选项。
	#include "/effects/sky/sky.glsl"
#endif

#ifdef OMNI_VERTEX // 顶点阶段：天空基础与天空贴图分开写。
#if defined OMNI_SKYBASIC_PASS // 天空基础顶点着色器。
out vec4 color; // 顶点色。

// 顶点主函数：原版天空渐变直接用顶点色。
void main(){
	gl_Position = ftransform(); // 用加载器的矩阵直接变换顶点。

	#ifdef OMNI_TAA // 开启时间抗锯齿时给顶点加本帧抖动。
		gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加抖动。
	#endif

	color = gl_Color; // 顶点色。
}
#elif defined OMNI_SKYTEXTURED_PASS // 天空贴图顶点着色器。
out vec3 v_color; // 顶点色。
out vec2 v_texCoord; // 纹理坐标。

// 顶点主函数：只传颜色与纹理坐标，日月判定在几何阶段。
void main(){
	gl_Position = ftransform(); // 用加载器的矩阵直接变换顶点。

	#ifdef OMNI_TAA // 开启时间抗锯齿时给顶点加本帧抖动。
		gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加抖动。
	#endif

	v_color = gl_Color.rgb; // 顶点色取三通道。
	v_texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0); // 纹理坐标。
}
#endif // 顶点程序分支结束。
#endif // 顶点阶段结束。

#ifdef OMNI_GEOMETRY // 几何阶段：只有主世界的天空贴图带它，用来区分太阳与月亮。
// 几何阶段输入三角形，输出三角带。
layout(triangles) in; // 输入三角形。
layout(triangle_strip, max_vertices = 3) out; // 输出三个顶点。

in vec3 v_color[]; // 顶点色数组。
in vec2 v_texCoord[]; // 纹理坐标数组。

out vec3 color; // 顶点色。
out vec2 texCoord; // 纹理坐标。
flat out float isMoon; // 是否是月亮，平面插值。

// 几何主函数：按纹理坐标跨度判定日月，再原样转发三角形。
void main(){
	float coordDiff = max(max(abs(v_texCoord[0].x - v_texCoord[1].x), // 第一条边在横轴上的跨度。
							  abs(v_texCoord[1].x - v_texCoord[2].x)), // 第二条边。
							  abs(v_texCoord[2].x - v_texCoord[0].x)); // 第三条边，取最大者。

	isMoon = float(coordDiff == 0.25); // 横轴跨度正好四分之一的是月亮，原程序用它区分。

	for (int i = 0; i < 3; i++){ // 逐个顶点转发。
		gl_Position = gl_in[i].gl_Position; // 位置照抄。

		color = v_color[i]; // 转发顶点色。
		texCoord = v_texCoord[i]; // 转发纹理坐标。

		EmitVertex(); // 发出顶点。
	}
	EndPrimitive(); // 结束三角形。
}
#endif // 几何阶段结束。

#if defined OMNI_FRAGMENT && defined OMNI_SKYBASIC_PASS // 天空基础片元着色器。
/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 gbufferOutput0; // 零号天体颜色。

in vec4 color; // 顶点色。

// 片元主函数：星点类型为关且没开资源包天空时丢弃，其余把顶点色叠进零号。
void main(){
	#if OMNI_STAR_TYPE < 2 // 星点关或点状时天空基础一般不用。
		#if !(OMNI_RESOURCEPACK_SKY && defined OMNI_OVERWORLD) // 资源包天空要原版天空底色与星空，这时照画。
			discard; // 直接丢弃。
		#endif
	#endif
	gbufferOutput0 = color; // 写原版天空渐变颜色。
}
#elif defined OMNI_FRAGMENT && defined OMNI_SKYTEXTURED_PASS // 天空贴图片元着色器。
// 纹理采样器：日月或天空盒贴图。
uniform sampler2D tex; // 天空贴图。

/* DRAWBUFFERS:0 */
layout(location = 0) out vec4 gbufferOutput0; // 零号天体颜色。

in vec3 color; // 顶点色。
in vec2 texCoord; // 纹理坐标。
flat in float isMoon; // 是否是月亮。

// 双线性取贴图：在图块内按四角纹素插值，比双线性更可控。
vec4 BilinearTexture(sampler2D texSampler, vec2 coord, vec2 texSize){
	coord = coord * texSize - 0.5; // 换成以纹素中心为原点的坐标。

	vec2 p = floor(coord); // 整数纹素。
	vec2 f = coord - p; // 小数偏移。

	ivec2 texelX = ivec2(p); // 左下角纹素。
	ivec2 texelW = texelX + 1; // 右上角纹素。

	return mix(mix(texelFetch(texSampler, texelX                   , 0), texelFetch(texSampler, ivec2(texelW.x, texelX.y), 0), f.x), // 先横向插值。
			   mix(texelFetch(texSampler, ivec2(texelX.x, texelW.y), 0), texelFetch(texSampler, texelW                   , 0), f.x), // 再横向插值。
			   f.y); // 最后纵向插值。
}

// 天空盒版双线性：每个图块边界内插值，避免跨图块取到相邻面。
vec4 BilinearTextureSkybox(sampler2D texSampler, vec2 coord, vec2 texSize){
	ivec2 grid = ivec2(floor(coord * vec2(3.0, 2.0))); // 天空盒是三乘二的图块排布。
	int gridSize = int(floor(texSize.y * 0.5)); // 每个图块的边长。
	grid *= gridSize; // 换成像素坐标。
	ivec4 border = ivec4(grid, grid + gridSize - 1); // 该图块的四条边界。

	coord = coord * texSize - 0.5; // 换成以纹素中心为原点的坐标。

	vec2 p = floor(coord); // 整数纹素。
	vec2 f = coord - p; // 小数偏移。

	ivec2 texelX = clamp(ivec2(p), border.xy, border.zw); // 左下角夹在图块内。
	ivec2 texelW = clamp(texelX + 1, border.xy, border.zw); // 右上角同样夹住。

	return mix(mix(texelFetch(texSampler, texelX                   , 0), texelFetch(texSampler, ivec2(texelW.x, texelX.y), 0), f.x), // 横向插值。
			   mix(texelFetch(texSampler, ivec2(texelX.x, texelW.y), 0), texelFetch(texSampler, texelW                   , 0), f.x), // 横向插值。
			   f.y); // 纵向插值。
}

// 片元主函数：月亮与天空盒各有开关，关闭时丢弃；资源包天空打开时全部原样叠加。
void main(){
	vec4 albedo = vec4(0.0); // 待填充的颜色。

	if (isMoon > 0.5){ // 月亮图块。
		#ifdef OMNI_MOON_TEXTURE // 开启月亮贴图时按是否在水下决定要不要画。
			if (isEyeInWater != 0) discard; // 水下不画月亮。
		#else
			#if !(OMNI_RESOURCEPACK_SKY && defined OMNI_OVERWORLD) // 资源包天空也要资源包的月亮，这时照画。
				discard; // 关闭月亮贴图时丢弃。
			#endif
		#endif

		#if OMNI_BILINEAR_MOON_TEXTURE // 月亮贴图按开关选双线性或普通采样。
			albedo = BilinearTexture(tex, texCoord, vec2(textureSize(tex, 0))); // 双线性采样。
		#else
			albedo = textureLod(tex, texCoord, 0.0); // 普通采样。
		#endif	
	}else{ // 天空盒图块，资源包天空时这里还包括太阳与自定义天空层。
		#if !OMNI_SKYBOX_TEXTURE // 关闭天空盒贴图时丢弃。
			#if !(OMNI_RESOURCEPACK_SKY && defined OMNI_OVERWORLD) // 资源包天空要资源包的天空层与太阳，这时照画。
				discard; // 丢弃。
			#endif
		#endif

		#if OMNI_BILINEAR_SKYBOX_TEXTURE // 天空盒按开关选双线性或普通采样。
			albedo = BilinearTextureSkybox(tex, texCoord, vec2(textureSize(tex, 0))); // 天空盒双线性采样。
		#else
			albedo = textureLod(tex, texCoord, 0.0); // 普通采样。
		#endif
	}
		
	albedo.rgb *= color; // 乘顶点色。

	gbufferOutput0 = albedo; // 写天体颜色，叠加混合进零号画面。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
