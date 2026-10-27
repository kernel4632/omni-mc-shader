/*
半透明绘制主体：把 iterationT 的水面与手持水四类程序合成一个主体文件。
来源：`Lib/Programs/Gbuffers/Water_VS.glsl`、`Water_FS.glsl`、`Hand_Water_VS.glsl`、`Hand_Water_FS.glsl`
  一比一移植；原程序用两个独立文件对，这里用 `OMNI_WATER_PASS` 与 `OMNI_HAND_WATER_PASS` 在一个文件里分开。
调用位置：各维度 `gbuffers_water`、`gbuffers_hand_water` 入口定义阶段宏与对应程序宏后引入本文件；
  入口按 `rendering/programs.json` 生成。
可复制示例：入口写 `#define OMNI_FRAGMENT 1`、`#define OMNI_WATER_PASS 1`、`#define OMNI_OVERWORLD 1`，
  再写 `#include "/rendering/translucent.glsl"`。
输出约定：水面写四号、六号、零号，对应 `DRAWBUFFERS:460`；手持半透明写四号、六号，对应 `DRAWBUFFERS:46`。
设计原因与取舍：
  水面与手持水都写半透明层的法线光照图与颜色材质，共用水体光学与波浪；区别在于水面按方块编号区分水、冰、
  普通方块，并用波浪法线造形，手持水只按贴图法线走。
  顶点阶段不引入 `effects/water/water.glsl`，它含只有片元能用的导数函数；只有海洋物理扩展存在时顶点才需要它算波高。
  iterationT 的 `Hand_Water_FS` 入口没有定义 `DIMENSION_MAIN`，所以手持水永远走非主世界分支，只用地表基础湿润；
  这里照原样保留这个行为，不复用 `OMNI_OVERWORLD` 判断。
*/
#ifndef OMNI_TRANSLUCENT_BODY_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_TRANSLUCENT_BODY_INCLUDED // 置上标记。

// 加载器输入声明，最先引入。
#include "/common/uniforms.glsl"
// 共用纯计算：曲线、法线编解码、打包与波浪辅助。
#include "/common/math.glsl"
// 时间抗锯齿选项：坐标换算要用它决定是否撤销抖动，必须先于坐标换算引入。
#include "/effects/clarity/antialiasing.glsl"
// 材质与视差：提供 `MATID_*` 与材质选项。
#include "/effects/shared/surface.glsl"
// 区块淡入：`omniChunkFade*` 一组纯计算，水面顶点取进度、片元按进度压透明度并丢弃。
#include "/effects/clarity/chunkfade.glsl"
// 时间噪声：片元抖动丢弃要读蓝噪声，顶点阶段只编译不调用。
#include "/common/noise.glsl"
// 水面与水雾：片元算波浪、视差与雨点，只在片元引入。
#ifdef OMNI_FRAGMENT
	// --- 水文件会读的加载器输入：必须先于水文件声明 ---
	uniform sampler2D gaux1; // 雨点第一张动画贴图。
	uniform sampler2D gaux2; // 雨点第二张动画贴图。
	uniform sampler2D gaux3; // 雨点第三张动画贴图。
	// 天气文件里的雨色与风偏移读取阳光、天光与露天标记，按调用前提给空全局；本程序不调用它们。
	vec3 colorShadowlight; // 阳光颜色。
	vec3 colorSkylight; // 天光颜色。
	// 只有水面程序且开了海洋物理扩展时才声明物理海浪的片元输入，手持水不参与，避免与顶点输出对不上。
	#if defined OMNI_WATER_PASS && defined PHYSICS_OCEAN
		#define PHYSICS_FS 1 // 请求水文件声明物理海浪的片元输入。
	#endif
	// 波浪、涟漪、物理海浪、湿润调制与水体光学。
	#include "/effects/shared/water.glsl"
	// 波浪模拟：提供 `omniWaveSimNormal` 与两张模拟场采样器，把玩家带起的波纹混进波法线；默认关闭。
	#include "/effects/shared/water/wavesim.glsl"
#endif
// 海洋物理扩展存在时顶点需要同一个文件里的波高函数。
#ifdef OMNI_VERTEX
	#ifdef PHYSICS_OCEAN
		#define PHYSICS_VS 1 // 请求水文件声明物理海浪的顶点输出。
		// 波浪与物理海浪。
		#include "/effects/shared/water.glsl"
	#endif
#endif
// 坐标换算：屏幕、视空间与深度互转，放在 `OMNI_TAA` 定义之后。
#include "/common/coordinates.glsl"
// 行星曲率：顶点阶段按相机相对水平距离把远处顶点下沉，选项与算法都在该文件。
#include "/effects/world/planet.glsl"

#ifdef OMNI_VERTEX // 顶点阶段：水面与手持水分开写。
#if defined OMNI_WATER_PASS // 水面顶点着色器。
// 方块实体编号：水、冰与普通方块靠它区分。
attribute vec4 mc_Entity;

// 传给片元的插值量。
out vec3 color; // 顶点色。
out vec2 texCoord; // 纹理坐标。
out vec3 viewPos; // 视空间位置。
#ifdef OMNI_TERRAIN_VS_TBN
	// 顶点切线属性，由模组或资源包提供。
	attribute vec4 at_tangent;
	out mat3 tbn; // 顶点切线基。
#endif
out vec2 blockLight; // 方块光与天光。
flat out float materialIDs; // 材质编号。
out float chunkFade; // 区块淡入进度，传给片元按进度压透明度并丢弃。


// 水面顶点主函数：海洋物理扩展存在时抬升水面，否则直接用原顶点。
void main(){
	#ifdef PHYSICS_OCEAN // 物理海浪：按物理扩展的波高抬升顶点。
		physics_localWaviness = texelFetch(physics_waviness, ivec2(gl_Vertex.xz) - physics_textureOffset, 0).r; // 读该处水深。
		vec4 finalPosition = vec4(gl_Vertex.x, gl_Vertex.y + physics_waveHeight(gl_Vertex.xz, PHYSICS_ITERATIONS_OFFSET, physics_localWaviness, physics_gameTime), gl_Vertex.z, gl_Vertex.w); // 按波高抬升纵坐标。
		physics_localPosition = finalPosition.xyz; // 记下抬升后的局部位置给片元。
		vec4 v_viewPos = gl_ModelViewMatrix * vec4(physics_localPosition, 1.0); // 转到视空间。
	#else // 无物理扩展时水面不做顶点位移。
		vec4 v_viewPos = gl_ModelViewMatrix * gl_Vertex; // 常规顶点变换。
	#endif

	vec3 planetViewPos = v_viewPos.xyz; // 复制水面视空间位置给行星曲率改写。
	omniPlanetCurvatureView(planetViewPos); // 行星曲率：远处水面顶点沿纵向下沉，模拟星球弯曲；关闭时为原样。
	v_viewPos.xyz = planetViewPos; // 写回改写后的视空间位置。

	float chunkFadeRaw = 1.0; // 加载器不提供淡入进度时保持一，等于水面一直完全显现。
	#ifdef IRIS_FEATURE_FADE_VARIABLE // 请求加载器特性后 `mc_chunkFade` 属性才存在。
		chunkFadeRaw = mc_chunkFade; // 读取原版区块淡入进度：未淡入时为负，淡入完成时为一。
	#endif
	chunkFade = omniChunkFadeValue(chunkFadeRaw); // 取正并夹到零到一，选项关闭时返回一。

	// 区块淡入的滑动档：把远处未淡入的水面从下方滑入，和地形共用同一个函数与判据。
	// 为什么先换到相机相对世界坐标：滑动量按水平距离算，视空间里相机是原点、拿不到距离。
	vec4 slideWorldPos = gbufferModelViewInverse * v_viewPos; // 视空间回到相机相对世界坐标。
	slideWorldPos.xyz = omniChunkFadeSlide(slideWorldPos.xyz, chunkFade, eyeBrightnessZeroSmooth, far); // 关闭或不在滑动档时原样返回。
	v_viewPos = gbufferModelView * slideWorldPos; // 滑动后再回到视空间投影。

	viewPos = v_viewPos.xyz; // 传给片元。

	gl_Position = gl_ProjectionMatrix * v_viewPos; // 投影到裁剪空间。

	#ifdef OMNI_TAA // 开启时间抗锯齿时给顶点加本帧抖动。
		gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加抖动。
	#endif

	color = gl_Color.rgb; // 顶点色取三通道。
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0); // 纹理坐标。

	#ifdef OMNI_TERRAIN_VS_TBN // 开关顶点切线时构造切线基。
		vec3 N = normalize(gl_NormalMatrix * gl_Normal); // 法线转到视空间。
		vec3 T = normalize(gl_NormalMatrix * at_tangent.xyz); // 切线转到视空间。
		vec3 B = cross(T, N) * sign(at_tangent.w); // 副切线由叉乘与手性得到。
		tbn = mat3(T, B, N); // 组装切线基。
	#endif

	vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy; // 原版光照图坐标。
	blockLight = saturate(lmcoord * 1.103449 - 0.0689656); // 重整到零到一。

	materialIDs = MATID_STAINEDGLASS; // 默认按染色玻璃处理，透明表面多是这样。

	if(mc_Entity.x == 0.0){ // 零编号是普通不透明表面。
		materialIDs = MATID_LAND; // 记为普通方块。
		gl_Position.z -= 1e-4; // 深度前移一点，避免和底面同层时闪烁。
	}

	if(mc_Entity.x == 8.0){ // 八编号是水。
		materialIDs = MATID_WATER; // 记为水。
	}

	if (mc_Entity.x == 79.0){ // 七十九编号是冰。
		materialIDs = MATID_ICE; // 记为冰。
	}
}
#elif defined OMNI_HAND_WATER_PASS // 手持水顶点着色器。
// 传给片元的插值量。
out vec3 color; // 顶点色。
out vec2 texCoord; // 纹理坐标。
out vec3 viewPos; // 视空间位置。
out vec2 blockLight; // 方块光与天光。


// 手持水顶点主函数：常规变换，无波浪。
void main(){
	vec4 v_viewPos = gl_ModelViewMatrix * gl_Vertex; // 顶点转到视空间。
	viewPos = v_viewPos.xyz; // 传给片元。
	gl_Position = gl_ProjectionMatrix * v_viewPos; // 投影到裁剪空间。

	#ifdef OMNI_TAA // 开启时间抗锯齿时给顶点加本帧抖动。
		gl_Position.xy = taaJitter * gl_Position.w + gl_Position.xy; // 叠加抖动。
	#endif

	color = gl_Color.rgb; // 顶点色。
	texCoord = vec2(gl_TextureMatrix[0] * gl_MultiTexCoord0); // 纹理坐标。
	vec2 lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy; // 原版光照图坐标。
	blockLight = saturate(lmcoord * 1.103449 - 0.0689656); // 重整到零到一。
}
#endif // 顶点阶段结束。
#endif // 顶点阶段结束。

#if defined OMNI_FRAGMENT && defined OMNI_WATER_PASS // 片元阶段：水面片元着色器。
// 纹理采样器：底色、法线、高光与雨点贴图。
uniform sampler2D tex; // 水面贴图（水、冰、玻璃各自的贴图）。
uniform sampler2D normals; // 法线贴图。
uniform sampler2D specular; // 高光贴图，本程序未直接读，保留声明以对齐原程序。

/* DRAWBUFFERS:460 */
layout(location = 0) out vec4 gbufferOutput4; // 四号半透明法线光照图。
layout(location = 1) out vec4 gbufferOutput6; // 六号半透明颜色材质。
#if MC_VERSION > 11605 // 新版才把水的贴图色写进零号画面作为遮罩。
	layout(location = 2) out vec4 gbufferOutput0; // 零号水遮罩与贴图色。
#endif

// 从顶点阶段接收的插值量。
in vec3 color; // 顶点色。
in vec2 texCoord; // 纹理坐标。
in vec3 viewPos; // 视空间位置。
#ifdef OMNI_TERRAIN_VS_TBN
	in mat3 tbn; // 切线基。
#endif
in vec2 blockLight; // 方块光。
flat in float materialIDs; // 材质编号。
in float chunkFade; // 区块淡入进度，按它压水面的透明度并丢弃未淡入的水像素。


// 水面片元主函数：算切线基、湿润、波浪法线，最后写半透明层。
void main(){
// 切线基：顶点没给时用屏幕导数推出来。
	vec2 duv1 = dFdx(texCoord); // 纹理坐标横向屏幕变化。
	vec2 duv2 = dFdy(texCoord); // 纹理坐标纵向屏幕变化。
	
	#ifndef OMNI_TERRAIN_VS_TBN // 顶点没提供切线基时现场构造。
		mat3 tbn = omniTangentBasis(dFdx(viewPos), dFdy(viewPos), duv1, duv2); // 由屏幕导数构造切线基。
	#endif


// 底色：贴图色乘顶点色。
	vec4 tex = textureGrad(tex, texCoord, duv1, duv2); // 按屏幕导数采贴图。
	tex.rgb *= color; // 乘顶点色。
	float materialAO = 1.0; // 材质遮蔽系数默认一：水面不读法线贴图，未开该功能时也不压暗。

	#ifdef OMNI_WHITE_DEBUG_WORLD
		tex.rgb = vec3(1.0); // 调试白光时全白。
	#endif


// 湿润：先算世界位置与朝向，再按维度挑分支。
	vec3 mcPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz + cameraPosition; // 还原世界位置。
	float NdotU = dot(tbn[2], gbufferModelView[1].xyz); // 表面法线与世上方向的夹角。

	#ifdef OMNI_ENABLE_PBR

		#ifdef OMNI_OVERWORLD // 主世界看降雨。
			#ifndef OMNI_DISABLE_LOCAL_PRECIPITATION // 默认按所在群系是否真的降水。
				float wet = wetness * (1.0 - eyeSnowySmooth) * (1.0 - eyeNoPrecipitationSmooth) + OMNI_SURFACE_WETNESS; // 降雨湿润加基础湿润。
			#else
				float wet = wetness + OMNI_SURFACE_WETNESS; // 只看整体降雨。
			#endif

			wet *= step(0.9, blockLight.y); // 只有露天才积雨。

			vec2 rainNormal = vec2(0.0); // 雨点法线横纵分量。
			if (wet > 1e-7){ // 确实湿了才加雨点。
				wet *= GetModulatedRainSpecular(mcPos); // 按位置调制湿润高光。
						
				float lightMask = saturate(blockLight.y * 10.0 - 9.0); // 只有露天才有雨点。
				if (isEyeInWater == 1) NdotU = -NdotU; // 在水下时朝向取反。

				#ifdef OMNI_RAIN_SPLASH_EFFECT // 开启雨点溅射时产生雨点法线。
					float splashStrength = saturate(NdotU * 2.0 - 1.0) * lightMask * 4.0; // 水面溅射强度更高。
					if (splashStrength > 0.0) rainNormal = GetRainNormal(mcPos, splashStrength, wet); // 得到雨点法线。
				#endif

				wet *= lightMask; // 非露天处压掉湿润。
				wet *= saturate(NdotU * 0.5 + 0.5); // 朝向权重。
			}

		#else // 下界与末地没有降雨。
			float wet = OMNI_SURFACE_WETNESS; // 只用基础湿润。

			wet *= GetModulatedRainSpecular(mcPos); // 仍按位置调制。
			wet *= saturate(NdotU * 0.5 + 0.5); // 朝向权重。
		#endif

	#else
		float wet = 0.0; // 关闭物理光照时不做湿润。
	#endif


// 波浪法线：水用波浪，冰与玻璃用贴图法线。
	vec3 waterNormal = vec3(0.0, 0.0, 1.0); // 默认朝外。

	bool iswater = materialIDs == MATID_WATER; // 是否为水。

	#ifdef PHYSICS_OCEAN // 物理海浪：直接取合成好的波法线。

		if (iswater){
				WavePixelData wave = physics_wavePixel(physics_localPosition.xz, physics_localWaviness, physics_iterationsNormal, physics_gameTime); // 一次算出该像素的波数据。
				waterNormal = mat3(gbufferModelView) * wave.normal; // 波法线转到视空间。
		}else{
			#ifdef MC_NORMAL_MAP
				vec4 materialNormal = omniMaterialNormal(textureGrad(normals, texCoord, duv1, duv2).rgb); // 采贴图法线，按选项缩放起伏并解出材质遮蔽。
				waterNormal = materialNormal.xyz; // 缩放后的切线空间法线。
				materialAO = materialNormal.w; // 材质遮蔽系数，未开材质遮蔽时为一。
			#endif

			waterNormal = tbn * waterNormal; // 转到视空间。

			#if defined OMNI_ENABLE_PBR && defined OMNI_OVERWORLD && defined OMNI_RAIN_SPLASH_EFFECT 
				waterNormal = normalize(waterNormal + mat3(gbufferModelView) * vec3(rainNormal.x, 0.0, rainNormal.y)); // 叠上雨点法线。
			#endif
		}

	#else // 无物理扩展时用波浪函数造形。

		if (iswater){
			vec3 simWorldPos = mcPos; // 视差改写前的世界位置：模拟场按它取坐标，不受波高偏移影响。
			#if OMNI_WATER_PARALLAX // 开启水面视差时按波高偏移采样位置。
				mcPos = GetWaterParallaxCoord(mcPos, normalize(viewPos.xyz * tbn)); // 找到真正可见的波面位置。
			#endif
			NdotU = saturate(NdotU + float(isEyeInWater == 1) * 2.0); // 在水下时朝向视为朝上。
			waterNormal = GetWavesNormal(mcPos, max(NdotU * 15.0 + 3.0, 0.0)); // 取波浪法线，逆光时更平。

			#ifdef OMNI_WAVE_SIM_ON // 波浪模拟：把玩家带起的模拟波法线按压强权重混进基础波法线。
				float simUpness = dot(tbn[2], gbufferModelView[1].xyz); // 水面法线与世上方向的夹角。
				vec4 simWave = omniWaveSimNormal(omniWaveSim2Tex, omniWaveStateTex, simWorldPos, simUpness); // 模拟法线与权重。
				waterNormal = normalize(mix(waterNormal, simWave.xyz, simWave.w)); // 权重为零时保持基础波法线。
			#endif

		}else{
			#ifdef MC_NORMAL_MAP
				vec4 materialNormal = omniMaterialNormal(textureGrad(normals, texCoord, duv1, duv2).rgb); // 采贴图法线，按选项缩放起伏并解出材质遮蔽。
				waterNormal = materialNormal.xyz; // 缩放后的切线空间法线。
				materialAO = materialNormal.w; // 材质遮蔽系数，未开材质遮蔽时为一。
				#ifdef OMNI_ENABLE_PBR
					waterNormal = mix(waterNormal, vec3(0.0, 0.0, 1.0), saturate(wet * 1.5)); // 越湿越接近平整水面。
				#endif
			#endif
		}

		waterNormal = tbn * waterNormal; // 转到视空间。

		#if defined OMNI_ENABLE_PBR && defined OMNI_OVERWORLD && defined OMNI_RAIN_SPLASH_EFFECT 
			waterNormal = normalize(waterNormal + mat3(gbufferModelView) * vec3(rainNormal.x, 0.0, rainNormal.y)); // 叠上雨点法线。
		#endif

		if (iswater){ // 水面额外把法线偏向水平，模拟水面的平铺感。
			vec3 viewDir = normalize(-viewPos.xyz); // 视线方向。
			#ifdef DISTANT_HORIZONS
				const float weight = 0.25; // 有远景时权重更高。
			#else
				const float weight = 0.07; // 常规权重。
			#endif
			waterNormal = normalize(waterNormal.xyz + (tbn[2] / (max(0.0, dot(tbn[2], viewDir)) + 0.001)) * weight); // 按掠射程度把法线拉向面法线。
		}

	#endif


	vec2 normalEnc = EncodeNormal(waterNormal); // 八面体编码法线。


// 区块淡入：按进度压水的透明度并丢弃未淡入的水像素；选项关闭时原样保留。
	#if OMNI_CHUNK_FADE > 0 // 只有开启才准备抖动并判断。
		#ifdef OMNI_TAA // 开时间抗锯齿用蓝噪声，抖动模式会随时间被平均掉。
			float chunkFadeDither = BlueNoiseTemporal().x; // 每帧变化的蓝噪声。
		#else // 否则用交错梯度噪声，不额外采样噪声贴图。
			float chunkFadeDither = InterleavedGradientNoise(gl_FragCoord.xy); // 每像素固定图案。
		#endif
		if (iswater && omniChunkFadeDiscard(chunkFade, chunkFadeDither)) discard; // 只丢弃水，冰与染色玻璃留着。
	#endif
	tex = omniChunkFadeWaterColor(tex, chunkFade); // 半透明层按进度压透明度，关闭时原样返回。
	tex.rgb *= materialAO; // 资源包法线蓝通道的材质遮蔽压到底色，未开时为一、不改变画面。


	gbufferOutput4 = vec4(normalEnc, blockLight); // 四号写法线与方块光。
	gbufferOutput6 = vec4(Pack2x8(tex.rg), Pack2x8(tex.ba), (materialIDs + 0.1) / 255.0, float(iswater)); // 六号打包颜色、材质编号与水遮罩。

	#if MC_VERSION > 11605 // 新版把非水像素的贴图色也写进零号，供后续读取。
		tex.a = materialIDs == MATID_LAND ? tex.a : 0.0; // 只有普通方块保留透明度。
		gbufferOutput0 = tex; // 零号写贴图色与水遮罩。
	#endif
}
#elif defined OMNI_FRAGMENT && defined OMNI_HAND_WATER_PASS // 片元阶段：手持水片元着色器。
// 纹理采样器：底色与法线。
uniform sampler2D tex; // 手持水贴图。
uniform sampler2D normals; // 法线贴图。

/* DRAWBUFFERS:46 */
layout(location = 0) out vec4 gbufferOutput4; // 四号半透明法线光照图。
layout(location = 1) out vec4 gbufferOutput6; // 六号半透明颜色材质。

// 从顶点阶段接收的插值量。
in vec3 color; // 顶点色。
in vec2 texCoord; // 纹理坐标。
in vec3 viewPos; // 视空间位置。
in vec2 blockLight; // 方块光。


// 手持水片元主函数：常规切线基与湿润，写半透明层。
void main(){
// 切线基：始终用屏幕导数推出来。
	vec2 duv1 = dFdx(texCoord); // 纹理坐标横向屏幕变化。
	vec2 duv2 = dFdy(texCoord); // 纹理坐标纵向屏幕变化。
	mat3 tbn = omniTangentBasis(dFdx(viewPos), dFdy(viewPos), duv1, duv2); // 由屏幕导数构造切线基。


// 底色：贴图色乘顶点色。
	vec4 albedo = textureGrad(tex, texCoord, duv1, duv2); // 按屏幕导数采贴图。
	albedo.rgb *= color; // 乘顶点色。

	#ifdef OMNI_WHITE_DEBUG_WORLD
		albedo.rgb = vec3(1.0); // 调试白光时全白。
	#endif


// 湿润：手持水没有降雨湿润，只用地表基础湿润并按半强与朝向缩放。
	#ifdef OMNI_ENABLE_PBR

		float NdotU = dot(tbn[2], gbufferModelView[1].xyz); // 表面法线与世上方向的夹角。

		float wet = OMNI_SURFACE_WETNESS; // 只用基础湿润，iterationT 的手持水入口不定义主世界宏，永远走这一支。
		wet *= 0.5; // 压半。
		wet *= saturate(NdotU * 0.5 + 0.5); // 朝向权重。

	#else
		float wet = 0.0; // 关闭物理光照时不做湿润。
	#endif


// 法线：按贴图法线，湿润拉平，并按开关压住极端法线。
	#ifdef MC_NORMAL_MAP
		vec4 materialNormal = omniMaterialNormal(textureGrad(normals, texCoord, duv1, duv2).rgb); // 采法线，按选项缩放起伏并解出材质遮蔽。
		vec3 normalTex = materialNormal.xyz; // 缩放后的切线空间法线。
		albedo.rgb *= materialNormal.w; // 材质遮蔽压到底色，未开时为一、不改变画面。
		#ifdef OMNI_ENABLE_PBR 
			normalTex = mix(normalTex, vec3(0.0, 0.0, 1.0), saturate(wet * 1.5)); // 越湿越接近平整水面。
		#endif
	#else
		vec3 normalTex = vec3(0.0, 0.0, 1.0); // 没有法线贴图时朝外。
	#endif

	vec3 viewNormal = tbn * normalize(normalTex); // 切线空间法线转到视空间。

	#ifdef OMNI_HAND_NORMAL_CLAMP
		vec3 viewDir = -normalize(viewPos); // 视线方向。
		viewNormal = normalize(viewNormal + tbn[2] * inversesqrt(saturate(dot(viewNormal, viewDir)) + 0.001)); // 压住极端法线。
	#endif

	vec2 normalEnc = EncodeNormal(viewNormal); // 八面体编码法线。


	gbufferOutput4 = vec4(normalEnc, blockLight); // 四号写法线与方块光。
	gbufferOutput6 = vec4(Pack2x8(albedo.rg), Pack2x8(albedo.ba), (MATID_STAINEDGLASS + 0.1) / 255.0, 1.0); // 六号打包颜色与材质编号。
}
#endif // 片元阶段结束。
#endif // 文件守卫结束。
