/*
地形表面采样与写出：片元阶段按开关走视差、各向异性过滤或屏幕导数采样，得到底色、高光与法线，并写出画面。
来源：iterationT `Lib/Programs/Gbuffers/Terrain_FS.glsl` 一比一移植。
职责：`SampleAnisotropic` 沿屏幕上的纹理压缩方向多采几步，`SampleTerrainSurface` 按开关统一取表面贴图，
  `WriteTerrainGbuffer` 把底色、法线光照与高光材质写进零、三、五号画面，`omniTerrainFragment` 是片元主函数体。
调用位置：由 `rendering/terrain.glsl` 的地形片元阶段引入，该文件的 `main` 只调用 `omniTerrainFragment()`。
可复制示例：
  `SampleTerrainSurface(tbn, texCoord, duv1, duv2, shadowVector, parallaxShadow, albedoTex, specularTex, normalTex, materialAO);`
  `WriteTerrainGbuffer(albedo, normalEnc, blockLightDirectional, blockLight, specularTex, materialIDs, wet, parallaxShadow);`
  `omniTerrainFragment();`  由片元入口调用
调用前提：由 `rendering/terrain.glsl` 引入，加载器输入 `tex`、`normals`、`specular`、`atlasSize`、`renderStage` 与
  插值量 `viewPos`、`textureResolution`、`gbufferOutput0/3/5/9` 由该文件声明；视差与材质函数由效果文件提供。
关键设计原因与取舍：三个采样函数与片元主函数体都只服务地形片元，用到地形专属的加载器输入与输出，所以独立成地形专属效果文件，
  不放进被多个程序共用的 `effects/ground/material.glsl`。
*/
#ifndef OMNI_TERRAIN_SURFACE_INCLUDED // 只引入一次，避免函数重复定义。
#define OMNI_TERRAIN_SURFACE_INCLUDED // 置上标记，后续再次引用直接跳过。

// 各向异性过滤：沿屏幕上的纹理压缩方向多采几步，换回更清晰的远处方块。
vec4 SampleAnisotropic(vec2 coord, vec2 duv1, vec2 duv2, inout vec3 normalTex, inout vec4 specularTex, out float materialAO){
	materialAO = 1.0; // 材质遮蔽系数默认一：没有法线贴图或没开遮蔽时都不压暗底色。
	vec2 atlasTiles = vec2(atlasSize) / textureResolution; // 图集里横纵各有多少图块。
	vec2 tilesCoord = coord * atlasTiles; // 坐标换到图块单位。

	// 采样方向由屏幕导数求出，参考原程序给出的着色器写法。
	mat2 qd = inverse(mat2(dFdx(tilesCoord), dFdy(tilesCoord))); // 屏幕导数矩阵求逆。
	qd = transpose(qd) * qd; // 转成对称矩阵。

	float d = determinant(qd); // 行列式。
	float t = (qd[0][0] + qd[1][1]) * 0.5; // 迹的一半。

	float D = sqrt(abs(t * t - d)); // 特征值差的半值。
	float V = t - D; // 较小的特征值。
	float v = t + D; // 较大的特征值。
	vec2 A = vec2(-qd[0][1], qd[0][0] - V); // 对应较小特征值的特征向量。
	A *= inversesqrt(V * dot(A, A) + 1e-20); // 归一化，避免除零。

	float lod = log2(inversesqrt(v) * textureResolution); // 由较大特征值推出采样层级。

	const float steps = OMNI_ANISOTROPIC_FILTERING_QUALITY; // 采样步数来自选项。
	const float rSteps = 1.0 / OMNI_ANISOTROPIC_FILTERING_QUALITY; // 每步的比例。

	A *= rSteps; // 特征向量缩放成每步位移。

	vec4 albedoSample = vec4(0.0); // 底色累加量。
	#ifdef OMNI_ANISOTROPIC_FILTERING_NORMAL_SPECULAR // 开关时连法线与高光一起过滤。
		vec3 normalSample = vec3(0.0); // 法线累加量。
		vec4 specularSample = vec4(0.0); // 高光累加量。
	#endif

	vec2 tilesBaseCoord = floor(tilesCoord); // 当前图块位置。

	for (float i = 0.5 - steps * 0.5; i < steps * 0.5; i++){ // 沿特征向量均匀取几步。
		vec2 sampleCoord = i * A; // 这一步的偏移。
		sampleCoord = (tilesBaseCoord + fract(tilesCoord + sampleCoord)) / atlasTiles; // 回到零到一坐标，图块内回绕避免跨块。

		vec4 sampleAlbedo = textureLod(tex, sampleCoord, lod); // 读一步底色。

		albedoSample += vec4(sampleAlbedo.rgb * sampleAlbedo.a, sampleAlbedo.a); // 颜色按透明度加权累加。

		#ifdef OMNI_ANISOTROPIC_FILTERING_NORMAL_SPECULAR

			#ifdef MC_NORMAL_MAP
				normalSample += textureLod(normals, sampleCoord, lod).rgb * sampleAlbedo.a; // 法线按透明度加权。
			#endif

			#ifdef MC_SPECULAR_MAP
				#if OMNI_TEXTURE_EMISSIVENESS_MODE == 0
					specularSample += textureLod(specular, sampleCoord, lod) * sampleAlbedo.a; // 仅硬编码模式也过滤高光。
				#endif
			#endif

		#endif
	}

	float weights = 1.0 / albedoSample.a; // 权重和的倒数。

	#ifdef OMNI_ANISOTROPIC_FILTERING_NORMAL_SPECULAR

		#ifdef MC_NORMAL_MAP
			vec4 materialNormal = omniMaterialNormal(normalSample * weights); // 归一化后解码法线，并按选项缩放起伏、取出材质遮蔽。
			normalTex = materialNormal.xyz; // 缩放后的切线空间法线。
			materialAO = materialNormal.w; // 材质遮蔽系数，未开材质遮蔽时为一。
		#endif

		#ifdef MC_SPECULAR_MAP
			#if OMNI_TEXTURE_EMISSIVENESS_MODE == 0
				specularTex = specularSample * weights; // 归一化高光。
			#else
				specularTex = textureLod(specular, coord, 0.0); // 其余模式不过滤高光，只取一次。
			#endif
		#endif

	#else

		#ifdef MC_NORMAL_MAP
			vec4 materialNormal = omniMaterialNormal(textureGrad(normals, coord, duv1, duv2).rgb); // 按屏幕导数采法线，并按选项缩放起伏、取出材质遮蔽。
			normalTex = materialNormal.xyz; // 缩放后的切线空间法线。
			materialAO = materialNormal.w; // 材质遮蔽系数，未开材质遮蔽时为一。
		#endif

		#ifdef MC_SPECULAR_MAP
			#if OMNI_TEXTURE_EMISSIVENESS_MODE == 0
				specularTex = textureGrad(specular, coord, duv1, duv2); // 仅硬编码模式按屏幕导数采高光。
			#else
				specularTex = textureLod(specular, coord, 0.0); // 其余模式只取一次。
			#endif
		#endif

	#endif
	
	return vec4(albedoSample.rgb * weights, textureLod(tex, coord, 0.0).a); // 颜色归一化，透明度取原始值。
}

// 表面采样：按开关走视差、各向异性过滤或屏幕导数采样，得到底色、高光与法线，并可能丢弃透明像素。
// `materialAO` 是资源包法线蓝通道给出的材质遮蔽，未开该功能时恒为一，调用方把它乘到底色。
void SampleTerrainSurface(mat3 tbn, vec2 coord, vec2 duv1, vec2 duv2, vec3 shadowVector, inout float parallaxShadow, out vec4 albedoTex, out vec4 specularTex, out vec3 normalTex, out float materialAO){
	materialAO = 1.0; // 默认不压暗：视差路径与没有法线的情形都保持一。
	#if OMNI_PARALLAX_MODE > 0 && defined MC_NORMAL_MAP // 开启视差且有法线贴图时走视差路径。

		normalTex = vec3(0.0, 0.0, 1.0); // 视差函数会写回法线。
		ivec2 parallaxTexel = ParallaxOcclusionMapping(coord, tbn, shadowVector, duv1, duv2, normalTex, parallaxShadow); // 找到可见交点。
		albedoTex = texelFetch(tex, parallaxTexel, 0); // 精确取交点底色。

		#if MC_VERSION >= 11605 && !defined IS_IRIS // 新版区分实体方块与透明方块，丢弃阈值不同。
			float alphaRef = renderStage == MC_RENDER_STAGE_TERRAIN_SOLID ? 0.004 : 0.1; // 实体方块用更小阈值。
		#else
			float alphaRef = 0.1; // 旧版与 Iris 统一用零点一。
		#endif
		if (albedoTex.a < alphaRef) discard; // 透明像素丢弃。

		#ifdef MC_SPECULAR_MAP
			specularTex = texelFetch(specular, parallaxTexel, 0); // 精确取交点高光。
		#else
			specularTex = vec4(0.0); // 没有高光贴图时全零。
		#endif

		#ifdef MC_NORMAL_MAP
			// 视差函数已经解出交点法线，这里补上法线倍率与材质遮蔽，让这两个选项在视差路径同样生效。
			// 为什么遮蔽要另取一次贴图：遮蔽存在法线贴图的蓝通道，视差函数只回传解好的法线，没带回原始通道。
			normalTex = omniMaterialNormalScale(normalTex); // 按选项缩放起伏。
			materialAO = omniMaterialAO(texelFetch(normals, parallaxTexel, 0).rgb); // 取交点处的材质遮蔽，未开时为一。
		#endif

	#else // 未开视差时按各向异性过滤或普通采样取贴图。

		#if OMNI_ANISOTROPIC_FILTERING_QUALITY > 0 // 开启各向异性过滤。

			normalTex = vec3(0.0, 0.0, 1.0); // 过滤函数会写回法线。
			specularTex = vec4(0.0); // 过滤函数会写回高光。
			albedoTex = SampleAnisotropic(coord, duv1, duv2, normalTex, specularTex, materialAO); // 各向异性取底色、表面与材质遮蔽。

			#if MC_VERSION >= 11605 && !defined IS_IRIS
				float alphaRef = renderStage == MC_RENDER_STAGE_TERRAIN_SOLID ? 0.004 : 0.1; // 丢弃阈值同视差路径。
			#else
				float alphaRef = 0.1; // 旧版与 Iris 统一。
			#endif
			if (albedoTex.a < alphaRef) discard; // 透明像素丢弃。

		#else // 不开过滤时按屏幕导数采一次。

			albedoTex = textureGrad(tex, coord, duv1, duv2); // 按屏幕导数采底色。

			#if MC_VERSION >= 11605 && !defined IS_IRIS
				float alphaRef = renderStage == MC_RENDER_STAGE_TERRAIN_SOLID ? 0.004 : 0.1; // 丢弃阈值同上。
			#else
				float alphaRef = 0.1; // 旧版与 Iris 统一。
			#endif
			if (albedoTex.a < alphaRef) discard; // 透明像素丢弃。

			#ifdef MC_NORMAL_MAP
				vec4 materialNormal = omniMaterialNormal(textureGrad(normals, coord, duv1, duv2).rgb); // 采法线并解出材质遮蔽。
				normalTex = materialNormal.xyz; // 缩放后的切线空间法线。
				materialAO = materialNormal.w; // 材质遮蔽系数，未开材质遮蔽时为一。
			#else
				normalTex = vec3(0.0, 0.0, 1.0); // 没有法线贴图时朝外。
			#endif

			#ifdef MC_SPECULAR_MAP
				#if OMNI_TEXTURE_EMISSIVENESS_MODE == 0
					specularTex = textureGrad(specular, coord, duv1, duv2); // 仅硬编码模式按屏幕导数采高光。
				#else
					specularTex = textureLod(specular, coord, 0.0); // 其余模式只取一次。
				#endif
			#else
				specularTex = vec4(0.0); // 没有高光贴图时全零。
			#endif
			
		#endif

	#endif
}

// 输出写入：把底色、法线光照与高光材质写进零、三、五号画面。
void WriteTerrainGbuffer(vec3 albedo, vec2 normalEnc, float blockLightDirectional, vec2 blockLight, vec4 specularTex, float materialIDs, float wet, float parallaxShadow){
	gbufferOutput0 = vec4(albedo, 1.0); // 零号写不透明底色。
	gbufferOutput3 = vec4(normalEnc, blockLightDirectional, blockLight.y); // 三号写法线与方块光。
	gbufferOutput5 = vec4(Pack2x8(specularTex.rg), Pack2x8(specularTex.ba), (materialIDs + 0.1) / 255.0, Pack2x8(vec2(wet, parallaxShadow))); // 五号打包高光、材质编号、湿润与视差阴影。
}
// 片元主函数体：按原程序顺序算切线基、视差、遮挡、湿润、法线与高光，并写出零、三、五、九号画面。
// 为什么自成函数：入口 `rendering/terrain.glsl` 只保留阶段结构，算法体集中在本文件便于查找与修改。
void omniTerrainFragment(){
// 切线基：顶点没给时用屏幕导数推出来。
	vec2 duv1 = dFdx(texCoord); // 纹理坐标横向屏幕变化。
	vec2 duv2 = dFdy(texCoord); // 纹理坐标纵向屏幕变化。
	
	#ifndef OMNI_TERRAIN_VS_TBN // 顶点没提供切线基时现场构造。
		vec3 dp1 = dFdx(viewPos); // 视空间位置横向变化。
		vec3 dp2 = dFdy(viewPos); // 视空间位置纵向变化。

		vec3 N = normalize(cross(dp1, dp2)); // 法线由两条切向叉乘得到。
		vec3 dp2perp = cross(dp2, N); // 与法线正交的纵向切向。
		vec3 dp1perp = cross(N, dp1); // 与法线正交的横向切向。

		vec3 T = normalize(dp2perp * duv1.x + dp1perp * duv2.x); // 由纹理导数解出切线。
		vec3 B = normalize(dp2perp * duv1.y + dp1perp * duv2.y); // 解出副切线。
		float invmax = inversesqrt(max(dot(T, T), dot(B, B))); // 归一化因子。
		mat3 tbn = mat3(T * invmax, B * invmax, N); // 组装切线基。
	#endif

	#ifdef OMNI_DIRECTIONAL_BLOCKLIGHT // 指向性方块光要用方块光的屏幕梯度。
		vec2 blockLightDir = vec2(dFdx(blockLight.x), dFdy(blockLight.x)); // 方块光的屏幕变化方向。
	#endif


// 各向异性过滤与视差：先准备阳光方向，再按开关走视差或过滤。
	#ifdef OMNI_END // 末地用末地版阴影相机方向。
		vec3 shadowVector = mat3(gbufferModelView) * shadowModelViewInverseEnd[2].xyz; // 阳光方向转到视空间。
	#else // 主世界与下界用加载器给的阴影相机方向。
		vec3 shadowVector = mat3(gbufferModelView) * shadowModelViewInverse[2].xyz; // 阳光方向转到视空间。
	#endif

	float parallaxShadow = saturate(dot(tbn[2], shadowVector) * 200.0); // 面朝阳光程度，作为视差自阴影初值。


	vec4 albedoTex = vec4(0.0); // 采样得到的底色。
	vec4 specularTex = vec4(0.0); // 采样得到的高光。
	vec3 normalTex = vec3(0.0, 0.0, 1.0); // 采样得到的法线。
	float materialAO = 1.0; // 采样得到的材质遮蔽，未开该功能时为一。
	SampleTerrainSurface(tbn, texCoord, duv1, duv2, shadowVector, parallaxShadow, albedoTex, specularTex, normalTex, materialAO); // 按开关统一采样表面贴图。

// 区块淡入：按进度抖动丢弃像素，新加载的区块逐渐显现；选项关闭时从不丢弃。
	#if OMNI_CHUNK_FADE > 0 // 只有开启才准备抖动并判断。
		#ifdef OMNI_TAA // 开时间抗锯齿用蓝噪声，抖动模式会随时间被平均掉。
			float chunkFadeDither = BlueNoiseTemporal().x; // 每帧变化的蓝噪声。
		#else // 否则用交错梯度噪声，不额外采样噪声贴图。
			float chunkFadeDither = InterleavedGradientNoise(gl_FragCoord.xy); // 每像素固定图案。
		#endif
		if (omniChunkFadeDiscard(chunkFade, chunkFadeDither)) discard; // 进度越小丢弃的像素越多。
	#endif


// 方块光：默认取原版方块光，指向性开启时再按表面朝向倾斜。
	float blockLightDirectional = blockLight.x; // 默认直接用原版方块光横轴。

	#ifdef OMNI_DIRECTIONAL_BLOCKLIGHT // 指向性方块光：按法线把方块光偏向一侧。
		float blockLightFwidth = abs(blockLightDir.x) + abs(blockLightDir.y); // 梯度大小，用来挡住跳变处。
		blockLightDir = normalize(vec2(tbn * vec3(blockLightDir, 1e-10))); // 梯度转到切线空间。

		float lightNormalWeight = dot(blockLightDir, normalTex.xy) * (1.0 - blockLight.x * 0.95) * OMNI_DIRECTIONAL_BLOCKLIGHT_STRENGTH + 1.0; // 表面朝向让光偏向。

		if (blockLightFwidth > 1e-5 && blockLight.x < 1.0) blockLightDirectional = clamp(blockLightDirectional * lightNormalWeight, 0.0, 0.9999); // 只在方块光未满且梯度稳定时改写。
	#endif


// 底色：贴图色乘顶点色。
	vec3 albedo = albedoTex.rgb * color; // 合成底色。
	albedo *= materialAO; // 资源包法线蓝通道的材质遮蔽压到底色，未开时为一、不改变画面。

	albedo = omniSeason(albedo, color); // Omni 额外功能：按游戏天数给植被上季节色，默认关闭。

	#ifdef OMNI_WHITE_DEBUG_WORLD
		albedo = color.bbb; // 调试白光时只留顶点色的蓝通道。
	#endif


// 湿润：按降雨、孔隙率与朝向算湿的程度，并叠加雨点法线。
	#ifdef OMNI_ENABLE_PBR

		vec3 mcPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz + cameraPosition; // 还原世界位置。
		float NdotU = dot(tbn[2], gbufferModelView[1].xyz); // 表面法线与世上方向的夹角，越朝上越易积水。

		#if defined OMNI_TEXTURE_PBR_POROSITY && OMNI_TEXTURE_PBR_FORMAT < 2 // 资源包自带孔隙率时按标准位宽解码。
			float porosity = saturate(specularTex.b * (255.0 / 63.0) - step(64.0 / 255.0, specularTex.b)); // 高位为孔隙率。
		#else
			float porosity = OMNI_TEXTURE_DEFAULT_POROSITY; // 否则用默认孔隙率。
		#endif

		#ifdef OMNI_OVERWORLD // 主世界的地表湿润看降雨。
			#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION // 默认按所在群系是否真的降水。
				float wet = wetness * (1.0 - eyeSnowySmooth) * (1.0 - eyeNoPrecipitationSmooth) + OMNI_SURFACE_WETNESS; // 降雨湿润加地表基础湿润。
			#else
				float wet = wetness + OMNI_SURFACE_WETNESS; // 强制局部降水时只看整体降雨。
			#endif

			wet *= saturate(abs(materialIDs - MATID_LAVA - 0.5) - 0.5); // 岩浆与火不沾水。
			wet *= step(0.9, blockLight.y); // 只有露天（天光接近满值）才积雨。

			vec2 rainNormal = vec2(0.0); // 雨点法线横纵分量。
			if (wet > 1e-7){ // 只有确实湿了才加雨点。
				wet *= GetModulatedRainSpecular(mcPos); // 按位置调制湿润高光。
				
				float lightMask = saturate(blockLight.y * 10.0 - 9.0); // 只有露天才有雨点。

				#ifdef OMNI_RAIN_SPLASH_EFFECT // 开启雨点溅射时产生雨点法线。
					float splashStrength = saturate(NdotU * 2.0 - 1.0) * lightMask * (2.0 - porosity); // 越朝上、露天、越不吸水，溅射越强。
					if (splashStrength > 0.0) rainNormal = GetRainNormal(mcPos, splashStrength, wet); // 得到雨点法线。
				#endif

				wet *= lightMask; // 非露天处压掉湿润。
				wet *= saturate(NdotU * 0.5 + 0.5); // 朝下的面湿润更弱。
			}
		#else // 下界与末地没有降雨，只用地表基础湿润。
			float wet = OMNI_SURFACE_WETNESS; // 取基础湿润。

			wet *= saturate(abs(materialIDs - MATID_LAVA - 0.5) - 0.5); // 岩浆与火不沾水。
			wet *= GetModulatedRainSpecular(mcPos); // 仍按位置调制。
			wet *= saturate(NdotU * 0.5 + 0.5); // 朝向权重。
		#endif

	#else
		float wet = 0.0; // 关闭物理光照时不做湿润。
	#endif


// 法线：湿润把法线往朝外方向拉平，雨点再叠一点扰动。
	#if defined MC_NORMAL_MAP && defined OMNI_ENABLE_PBR
		normalTex = mix(normalize(normalTex), vec3(0.0, 0.0, 1.0), saturate(wet * (1.6 - porosity * 0.6))); // 越湿越接近平整水面。
	#endif


	vec3 viewNormal = tbn * normalize(normalTex); // 切线空间法线转到视空间。

	#if defined OMNI_ENABLE_PBR && defined OMNI_OVERWORLD && defined OMNI_RAIN_SPLASH_EFFECT 
		viewNormal = normalize(viewNormal + mat3(gbufferModelView) * vec3(rainNormal.x, 0.0, rainNormal.y)); // 叠上雨点法线。
	#endif

	#ifdef OMNI_TERRAIN_NORMAL_CLAMP
		vec3 viewDir = -normalize(viewPos); // 视线方向。
		viewNormal = normalize(viewNormal + tbn[2] * inversesqrt(saturate(dot(viewNormal, viewDir)) + 0.001)); // 压住掠射角处的极端法线。
	#endif

	vec2 normalEnc = EncodeNormal(viewNormal); // 八面体编码法线。


// 积雪覆盖：把雪按露天程度与朝向叠到底色，默认关闭时不执行。
	#ifdef OMNI_SNOW_OVERLAY
		// 世界位置：视空间位置回到相机相对世界坐标，再加上相机绝对位置。
		vec3 snowWorldPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz + cameraPosition;
		// 带贴图扰动的世界法线：视空间法线转到世界。
		vec3 snowWorldNormal = mat3(gbufferModelViewInverse) * viewNormal;
		// 几何面世界法线：切线基第三列转到世界，用来判断面的朝向。
		vec3 snowWorldFlatNormal = mat3(gbufferModelViewInverse) * tbn[2];
		albedo = omniSnowOverlay(albedo, snowWorldPos, snowWorldNormal, snowWorldFlatNormal, blockLight.y);
	#endif


// 高光：按资源包编码取出，并给红石线一个最小发光。
	#if defined MC_SPECULAR_MAP && OMNI_TEXTURE_PBR_FORMAT == 2
		specularTex.a = specularTex.b; // `PTGI` 编码把自发光放在蓝通道，转到透明度通道。
	#endif

	#if defined OMNI_ENABLE_PBR && OMNI_TEXTURE_PBR_FORMAT != 1
		if (materialIDs == MATID_REDSTONE && color.b == 0.0){ // 红石线的基础色蓝通道为零，可用来识别。
			float power = color.r; // 用红通道当强度。
			power = saturate(power * 1.1 - 0.1) * step(0.3, power); // 压掉弱信号。
			specularTex.a = max(specularTex.a, power * power * 0.3); // 给它一个最小自发光。
		}
	#endif


	WriteTerrainGbuffer(albedo, normalEnc, blockLightDirectional, blockLight, specularTex, materialIDs, wet, parallaxShadow); // 统一写出零、三、五号画面。

	#if defined OMNI_SHADER_GRASS && defined OMNI_OVERWORLD
		// 九号画面：红通道记方块编号，绿通道记生物群系，供下一帧几何阶段的草丛查询。
		// 为什么记成字节：编号和生物群系都是小整数，八位够用，跨帧查询不需要更高精度。
		gbufferOutput9 = vec4(blockID / 255.0, float(biome & 255) / 255.0, 0.0, 1.0); // 归一化到零到一存进八位画面。
	#endif
}
#endif // OMNI_TERRAIN_SURFACE_INCLUDED 结束。
