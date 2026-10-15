"""效果回归：检查选项接入、预处理分支与算法边界，不宣称像素效果。

示例 python -m unittest discover -s tests；全部使用离线展开，不建立显卡上下文。
"""
import unittest  # 保留标准测试入口。
import re  # 从实际公式提取固定阈值，拒绝未定义的顺序。
import subprocess  # 用真实预处理器验证开关分支。
import tempfile  # 探针源码只写入临时目录。
from pathlib import Path  # 临时阶段文件交给项目编译器。
import build  # 读取真实展开源码与原生选项。

class EffectTests(unittest.TestCase):
    """逐个效果核对选项单源、算法接入和默认路径。"""
    def test_fixed_smoothstep_edges_are_ordered(self):
        """固定阈值必须严格递增，避免驱动自行解释未定义计算。"""
        for path in (build.SHADERS/"effects").glob("*.glsl"):
            text = path.read_text(encoding="utf-8")  # 只检查自有效果，不改第三方源码。
            for match in re.finditer(r"smoothstep\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,", text):
                with self.subTest(path=path.name, formula=match[0]):  # 失败直接指出公式所在文件。
                    self.assertLess(float(match[1]),float(match[2]))  # 相等或反序都不受语言保证。

    def test_agx_tone_mapping_is_selectable(self):
        """AgX 通过色调映射选项接入最终显示，简单路径仍然保留。"""
        found,_,_ = build.configuration()  # 原生定义仍是唯一默认值来源。
        self.assertIn("OMNI_TONE_MAP",found); self.assertEqual(found["OMNI_TONE_MAP"].values,("0","1"))  # 菜单提供两种映射。
        source = build.expand(build.SHADERS/"world0/final.fsh")  # 从加载器实际入口展开。
        self.assertIn("omniToneMapAgx",source)  # 最终显示包含 AgX 曲线。
        self.assertIn("omniToneMapSimple",source)  # 简单有理映射没有被删除。
        self.assertIn("omniToneMap(color)",source)  # 计算路径由选项统一分派。

    def test_ordered_dither_applies_before_clamp(self):
        """有序抖动在显示编码之后打散色带，选项可关闭。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_DITHER",found); self.assertEqual(found["OMNI_DITHER"].values,("0","1"))  # 默认与关闭值来自原生定义。
        text = (build.SHADERS/"effects/color.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniBayer",text)  # 有序矩阵阈值独立成函数。
        self.assertIn("omniSrgb(clamp(color,0.0,1.0))",text)  # 抖动发生在显示编码之后。
        self.assertIn("gl_FragCoord.xy",text)  # 抖动按真实像素坐标取样。

    def test_bloom_threshold_and_radius_are_adjustable(self):
        """泛光阈值与半径都是可调参数，替换原先写死的数值。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_BLOOM_THRESHOLD",found); self.assertIn("OMNI_BLOOM_RADIUS",found)  # 两个参数由泛光源码定义。
        text = (build.SHADERS/"effects/bloom.glsl").read_text(encoding="utf-8")
        self.assertIn("lum - OMNI_BLOOM_THRESHOLD",text)  # 阈值参与光晕筛选。
        self.assertIn("* OMNI_BLOOM_RADIUS",text)  # 半径参与采样偏移。

    def test_shadow_bias_and_offset_are_adjustable(self):
        """阴影比较偏置与法线偏移都是可调参数，替换原先写死的余量与抬升距离。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_SHADOW_BIAS",found); self.assertIn("OMNI_SHADOW_OFFSET",found)  # 两个参数由阴影源码定义。
        text = (build.SHADERS/"effects/shadow.glsl").read_text(encoding="utf-8")
        self.assertIn("p.z - OMNI_SHADOW_BIAS",text)  # 偏置参与深度比较。
        self.assertIn("n * OMNI_SHADOW_OFFSET",text)  # 法线偏移参与采样点抬升。

    def test_horizon_ao_is_selectable_and_expands(self):
        """地平线环境遮蔽通过算法选项接入合成，螺旋路径仍然保留。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_AO_MODE",found); self.assertEqual(found["OMNI_AO_MODE"].values,("0","1"))  # 两种遮蔽算法可选。
        text = (build.SHADERS/"effects/ambient.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniHorizonOcclusion",text)  # 地平线积分独立成函数。
        self.assertIn("float omniSpiralOcclusion",text)  # 旧螺旋路径没有被删除。
        self.assertIn("vec2 omniHorizon",text)  # 每方向地平线搜索独立成函数，并返回有效标记。
        self.assertIn("if (!found) return 0.0;",text)  # 无有效邻点时这一片不得当成最大遮挡。
        source = build.expand(build.SHADERS/"world0/composite.fsh")  # 从实际合成入口展开全部引用。
        self.assertIn("omniHorizonOcclusion",source)  # 合成阶段包含地平线遮蔽。

    def test_lens_flare_uses_scene_highlight(self):
        """镜头耀斑在最终显示叠加，光源强度取自现有亮部且可关闭。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_LENS_FLARE",found); self.assertEqual(found["OMNI_LENS_FLARE"].values,("0","1"))  # 耀斑可开关。
        text = (build.SHADERS/"effects/lens.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniLensFlare",text)  # 耀斑独立成函数。
        self.assertIn("bool omniSunScreen",text)  # 屏幕太阳位置独立成函数。
        self.assertIn("texture(colortex0,sunUv)",text)  # 光源强度来自现有亮部而非新附件。
        source = build.expand(build.SHADERS/"world0/final.fsh")  # 从实际最终入口展开。
        self.assertIn("omniLensFlare",source)  # 最终显示包含耀斑。

    def test_bokeh_aperture_shape_modulates_focus(self):
        """散景光圈形状通过选项调制失焦采样半径，圆形路径仍可保留。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_BOKEH_SHAPE",found); self.assertEqual(found["OMNI_BOKEH_SHAPE"].values,("0","1"))  # 光圈形状可切换。
        text = (build.SHADERS/"effects/lens.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniApertureRadius",text)  # 多边形边界半径独立成函数。
        self.assertIn("radius*omniApertureRadius(angle)",text)  # 景深采样半径被光圈形状调制。

    def test_cloud_shadow_uses_density(self):
        """云影从地表沿光线步进云密度，只衰减主世界直射光且可关闭。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_CLOUD_SHADOW",found); self.assertEqual(found["OMNI_CLOUD_SHADOW"].values,("0","1"))  # 云影可开关。
        self.assertIn("OMNI_CLOUD_THICKNESS",found)  # 云层厚度是独立可调参数。
        self.assertIn("OMNI_CLOUD_SCALE",found)  # 云块尺度是独立可调参数。
        self.assertIn("OMNI_CLOUD_SILVER",found)  # 银边受光是独立可调参数。
        text = (build.SHADERS/"effects/cloud.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniCloudShadow",text)  # 云影独立成函数。
        self.assertIn("OMNI_CLOUD_MODE == 0",text)  # 关闭云显示时不再产生云影。
        self.assertIn("omniCloudDensity(p)",text)  # 复用同一云密度来源。
        sun = (build.SHADERS/"effects/sunlight.glsl").read_text(encoding="utf-8")
        self.assertIn("omniCloudShadow(world)",sun)  # 直射光按云影衰减。
        source = build.expand(build.SHADERS/"world0/gbuffers_terrain.fsh")  # 从地形入口展开。
        self.assertIn("omniCloudShadow",source)  # 地形照明包含云影。

    def test_planar_cloud_mode_is_selectable(self):
        """平面云层作为第四种云算法接入，复用分形密度且不改既有模式。"""
        found,_,_ = build.configuration()
        self.assertEqual(found["OMNI_CLOUD_MODE"].values,("0","1","2","3"))  # 菜单包含平面模式。
        text = (build.SHADERS/"effects/cloud.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniPlanarClouds",text)  # 平面云层独立成函数。
        self.assertIn("float omniPlanarDensity",text)  # 平面密度独立成函数。
        self.assertIn("OMNI_CLOUD_MODE == 3",text)  # 平面模式由模式选项分派。

    def test_underwater_volumetric_shafts(self):
        """水下体积光沿视线步进阴影，接入合成雾且可关闭。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_UNDERWATER_FOG",found); self.assertEqual(found["OMNI_UNDERWATER_FOG"].values,("0","1"))  # 水下光柱可开关。
        text = (build.SHADERS/"effects/fog.glsl").read_text(encoding="utf-8")
        self.assertIn("isEyeInWater == 1",text)  # 只有水下才执行光柱。
        self.assertIn("omniShadow(sampleWorld,sampleNormal)",text)  # 光柱来自真实阴影可见性。
        source = build.expand(build.SHADERS/"world0/composite.fsh")  # 从实际合成入口展开。
        self.assertIn("vec3 omniFog",source)  # 合成阶段包含雾主体。

    def test_height_fog_parameters_are_adjustable(self):
        """高度雾的基准高度与衰减是可调参数，替换原先写死的数值。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_FOG_HEIGHT",found); self.assertIn("OMNI_FOG_SCALE",found)  # 两个参数由雾源码定义。
        text = (build.SHADERS/"effects/fog.glsl").read_text(encoding="utf-8")
        self.assertIn("- OMNI_FOG_HEIGHT",text)  # 高度基准参与密度计算。
        self.assertIn("*OMNI_FOG_SCALE)",text)  # 衰减参与密度计算。

    def test_reflection_denoise_filters_by_depth(self):
        """反射去噪按命中深度加权邻点，旧五点路径仍可保留。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_REFLECTION_DENOISE",found); self.assertEqual(found["OMNI_REFLECTION_DENOISE"].values,("0","1"))  # 去噪可开关。
        text = (build.SHADERS/"effects/reflection.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniReflectionFilter",text)  # 去噪独立成函数。
        self.assertIn("omniReflectionFilter(hitUv,target.z,roughness)",text)  # 使用命中深度做相似度判断。
        self.assertIn("OMNI_REFLECTION_DENOISE == 1",text)  # 旧路径由选项分派保留。

    def test_reflection_fallback_uses_full_sky(self):
        """屏幕外反射回退复用天空、云与氛围的同一套合成，而不是只有纯天空色。"""
        text = (build.SHADERS/"effects/reflection.glsl").read_text(encoding="utf-8")
        self.assertIn("omniAtmosphere(omniCloud(omniSky(skyDirection)",text)  # 回退色与背景天空一致。
        self.assertIn('#include "/effects/cloud.glsl"',text)  # 反射确实引入了云。
        self.assertIn('#include "/effects/atmosphere.glsl"',text)  # 反射确实引入了氛围。

    def test_sky_brightness_parameters_are_adjustable(self):
        """日落、太阳与月亮亮度都是可调参数，替换原先写死的倍率。"""
        found,_,_ = build.configuration()
        for name in ("OMNI_SUNSET_STRENGTH","OMNI_SUN_DISK","OMNI_MOON_DISK"):
            self.assertIn(name,found)  # 每个参数都由天空源码定义。
        text = (build.SHADERS/"effects/sky.glsl").read_text(encoding="utf-8")
        self.assertIn("* OMNI_SUNSET_STRENGTH",text)  # 日落强度参与着色。
        self.assertIn("* OMNI_SUN_DISK",text)  # 太阳亮度参与着色。
        self.assertIn("* OMNI_MOON_DISK",text)  # 月亮亮度参与着色。

    def test_atmosphere_strengths_are_adjustable(self):
        """极光、彩虹与散射强度都是可调参数，替换原先写死的倍率。"""
        found,_,_ = build.configuration()
        for name in ("OMNI_AURORA_STRENGTH","OMNI_RAINBOW_STRENGTH","OMNI_SCATTER_STRENGTH"):
            self.assertIn(name,found)  # 每个参数都由氛围源码定义。
        text = (build.SHADERS/"effects/atmosphere.glsl").read_text(encoding="utf-8")
        self.assertIn("*OMNI_AURORA_STRENGTH",text)  # 极光强度参与着色。
        self.assertIn("*OMNI_RAINBOW_STRENGTH",text)  # 彩虹强度参与着色。
        self.assertIn("*OMNI_SCATTER_STRENGTH",text)  # 散射强度参与着色。

    def test_vegetation_wind_parameters_are_adjustable(self):
        """植被摆动强度与速度都是可调参数，替换原先写死的振幅与频率。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_WIND_STRENGTH",found); self.assertIn("OMNI_WIND_SPEED",found)  # 两个参数由植被源码定义。
        text = (build.SHADERS/"effects/vegetation.glsl").read_text(encoding="utf-8")
        self.assertIn("*OMNI_WIND_SPEED",text)  # 速度参与相位。
        self.assertIn("*OMNI_WIND_STRENGTH",text)  # 强度参与位移。

    def test_temporal_denoise_rotates_noise(self):
        """时序噪声逐帧旋转相位，地平线遮蔽在时间抗锯齿下可重建去噪。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_TEMPORAL_DENOISE",found); self.assertEqual(found["OMNI_TEMPORAL_DENOISE"].values,("0","1"))  # 时序重建可开关。
        aa = (build.SHADERS/"effects/antialiasing.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniTemporalNoise",aa)  # 时序噪声独立成函数。
        self.assertIn("frameCounter%64",aa)  # 相位逐帧旋转。
        ambient = (build.SHADERS/"effects/ambient.glsl").read_text(encoding="utf-8")
        self.assertIn("omniTemporalNoise(vec2(gl_FragCoord.xy))",ambient)  # 遮蔽相位使用时序噪声。
        source = build.expand(build.SHADERS/"world0/composite.fsh")  # 从实际合成入口展开。
        self.assertIn("omniTemporalNoise",source)  # 合成阶段包含时序重建。

    def test_nether_palette_is_selectable(self):
        """下界氛围色按方向噪声混合，接入下界天空且可回退到加载器雾色。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_NETHER_COLOR",found); self.assertEqual(found["OMNI_NETHER_COLOR"].values,("0","1"))  # 下界氛围色可开关。
        text = (build.SHADERS/"effects/sky.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniNetherColor",text)  # 下界色独立成函数。
        self.assertIn("OMNI_NETHER_COLOR == 1",text)  # 回退路径由选项分派保留。
        source = build.expand(build.SHADERS/"world-1/composite.fsh")  # 从下界合成入口展开。
        self.assertIn("omniNetherColor",source)  # 下界天空包含程序化氛围色。

    def test_analytic_atmosphere_scattering(self):
        """解析大气散射作为可选近似接入氛围，不依赖外部查找表。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_ATMOSPHERE_SCATTER",found); self.assertEqual(found["OMNI_ATMOSPHERE_SCATTER"].values,("0","1"))  # 散射可开关。
        text = (build.SHADERS/"effects/atmosphere.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniAirScattering",text)  # 散射独立成函数。
        self.assertIn("omniAirScattering(direction)",text)  # 氛围阶段叠加散射。
        source = build.expand(build.SHADERS/"world0/composite.fsh")  # 从实际合成入口展开。
        self.assertIn("omniAirScattering",source)  # 合成阶段包含散射。

    def test_end_fog_is_selectable(self):
        """末地雾提供紫色漩涡与虚空暗色，接入末地雾路径且可回退。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_END_FOG",found); self.assertEqual(found["OMNI_END_FOG"].values,("0","1"))  # 末地雾可开关。
        text = (build.SHADERS/"effects/fog.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniEndFog",text)  # 末地雾独立成函数。
        self.assertIn("OMNI_END_FOG == 1",text)  # 回退路径由选项分派保留。
        source = build.expand(build.SHADERS/"world1/composite.fsh")  # 从末地合成入口展开。
        self.assertIn("omniEndFog",source)  # 末地雾进入合成阶段。

    def test_water_bump_detail_feeds_normal(self):
        """水波凹凸细节叠加到解析波高度，参与法线有限差分且可关闭。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_WATER_BUMP",found); self.assertEqual(found["OMNI_WATER_BUMP"].values,("0","1"))  # 凹凸细节可开关。
        text = (build.SHADERS/"effects/water.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniWaterDetail",text)  # 细节独立成函数。
        self.assertIn("float omniWaterHeight",text)  # 合成高度独立成函数。
        self.assertIn("omniWaterHeight(p,world.y)",text)  # 法线重心样本使用合成高度。
        self.assertIn("omniWaterHeight(p+vec2(0.08,0.0),world.y)",text)  # 有限差分包含细节。

    def test_ocean_vertex_displacement_uses_same_height(self):
        """物理海浪在顶点抬升水面，并与法线共用同一高度函数且可关闭。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_OCEAN_WAVES",found); self.assertEqual(found["OMNI_OCEAN_WAVES"].values,("0","1"))  # 海浪可开关。
        water = (build.SHADERS/"effects/water.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniOceanHeight",water)  # 海浪高度独立成函数。
        self.assertIn("omniOceanHeight(p)+omniWave(p,relativeHeight)",water)  # 法线与顶点同源。
        terrain = (build.SHADERS/"rendering/terrain.glsl").read_text(encoding="utf-8")
        self.assertIn("omniOceanHeight((waterWorld+cameraPosition).xz)",terrain)  # 顶点按海浪抬升。
        source = build.expand(build.SHADERS/"world0/gbuffers_water.vsh")  # 从水面顶点入口展开。
        self.assertIn("omniOceanHeight",source)  # 顶点阶段包含海浪位移。

    def test_water_optics_are_adjustable(self):
        """水体吸收、散射与波速都是可调参数，且共用同一份光学常数。"""
        found,_,_ = build.configuration()
        for name in ("OMNI_WATER_ABSORB_R","OMNI_WATER_ABSORB_G","OMNI_WATER_ABSORB_B",
                     "OMNI_WATER_SCATTER_R","OMNI_WATER_SCATTER_G","OMNI_WATER_SCATTER_B","OMNI_WAVE_SPEED","OMNI_WAVE_SCALE"):
            self.assertIn(name,found)  # 每个参数都由效果源码定义。
        water = (build.SHADERS/"effects/water.glsl").read_text(encoding="utf-8")
        self.assertIn("const vec3 omniWaterAbsorbance = vec3(OMNI_WATER_ABSORB_R",water)  # 吸收只由选项组成一处向量。
        self.assertIn("omniWaterTransmit",water)  # 吸收与散射共用一个函数。
        fog = (build.SHADERS/"effects/fog.glsl").read_text(encoding="utf-8")
        self.assertIn("omniWaterTransmit(color,distance)",fog)  # 水下雾复用同一份水体光学常数。

    def test_climate_snow_and_wet(self):
        """气候温度按高度与噪声估计，驱动自然积雪与湿润且可回退手动值。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_CLIMATE",found); self.assertEqual(found["OMNI_CLIMATE"].values,("0","1"))  # 气候覆盖可开关。
        text = (build.SHADERS/"effects/material.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniTemperature",text)  # 温度估计独立成函数。
        self.assertIn("1.0-smoothstep(0.10,0.30,temperature)",text)  # 正序插值后取反，冷处积雪且不触发未定义计算。
        self.assertIn("wetness*(0.5+0.5*temperature)",text)  # 暖处湿润权重更高，与菜单说明一致。
        self.assertIn("OMNI_CLIMATE == 1",text)  # 手动回退路径由选项分派保留。
        source = build.expand(build.SHADERS/"world0/gbuffers_terrain.fsh")  # 从地形入口展开。
        self.assertIn("omniTemperature",source)  # 地形表面包含气候覆盖。

    def test_ggx_specular_highlight(self):
        """镜面高光用 GGX 分布接入直接光，材质粗糙度与金属来自表面参数。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_SPECULAR",found); self.assertEqual(found["OMNI_SPECULAR"].values,("0","1"))  # 镜面可开关。
        text = (build.SHADERS/"effects/sunlight.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniSpecular",text)  # 镜面独立成函数。
        self.assertIn("omniSpecular(normal,world,materialParams,sun,shadow)",text)  # 直接光叠加镜面。
        self.assertIn("materialParams",text)  # 材质参数进入光照。
        source = build.expand(build.SHADERS/"world0/gbuffers_terrain.fsh")  # 从地形入口展开。
        self.assertIn("omniSpecular",source)  # 地形光照包含镜面高光。

    def test_light_color_temperature_is_adjustable(self):
        """日月与方块光色温都是可调参数，默认零等于原行为。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_SUN_TINT",found); self.assertIn("OMNI_BLOCKLIGHT_TINT",found)  # 两个色温参数由光照源码定义。
        self.assertEqual(found["OMNI_SUN_TINT"].default,"0.0")  # 默认中性，不改变现有画面。
        text = (build.SHADERS/"effects/sunlight.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniTint",text)  # 色温换算独立成函数。
        self.assertIn("omniTint(OMNI_SUN_TINT)",text)  # 直射光应用色温。
        self.assertIn("omniTint(OMNI_BLOCKLIGHT_TINT)",text)  # 方块光应用色温。

    def test_edge_adaptive_upscale_is_optional(self):
        """边缘自适应重采样作为最终显示前的可选滤波，默认关闭保持原行为。"""
        found,_,_ = build.configuration()
        self.assertEqual(found["OMNI_UPSCALE"].values,("false","true"))  # 上采样为开关选项。
        self.assertEqual(found["OMNI_UPSCALE"].default,"false")  # 默认关闭，不由文件保护宏偷偷启用。
        text = (build.SHADERS/"effects/upscale.glsl").read_text(encoding="utf-8")
        self.assertFalse(any(line.strip() == "#define OMNI_UPSCALE" for line in text.splitlines()))  # 检查未替换选项的原始源码，避免离线配置掩盖重名。
        self.assertIn("vec3 omniUpscale",text)  # 重采样独立成函数。
        self.assertIn("mix(color,sum/weight,strength)",text)  # 平坦区收敛为原颜色。
        source = build.expand(build.SHADERS/"world0/final.fsh")  # 从最终显示入口展开。
        self.assertIn("omniUpscale",source)  # 最终显示包含可选重采样。

    def test_upscale_switch_survives_real_preprocessing(self):
        """原始默认源码必须关闭，上采样选项开启后才进入启用分支。"""
        found,_,_ = build.configuration()  # 选项替换沿用真实菜单定义。
        source = "#version 330 compatibility\n" + build.expand(build.SHADERS/"effects/upscale.glsl")  # 从真实效果文件展开依赖。
        source += "\n#ifdef OMNI_UPSCALE\nconst bool upscaleEnabled = true;\n#else\nconst bool upscaleEnabled = false;\n#endif\n"  # 用可观察输出标出实际选中的分支。
        defaults = {name: option.default for name,option in found.items()}  # 开启时仅修改目标选项。
        with tempfile.TemporaryDirectory() as temporary:
            shader = Path(temporary)/"probe.frag"  # 不碰项目入口和构建缓存。
            for enabled,text in ((False,source),(True,build.option_source(source,found,defaults|{"OMNI_UPSCALE":"true"}))):
                with self.subTest(enabled=enabled):  # 分别检查原始默认和加载器式替换。
                    shader.write_text(text,encoding="utf-8")  # 每次用同一实际预处理器读取探针。
                    result = subprocess.run([str(build.tool("glslang")),"-E",str(shader)],capture_output=True,text=True,encoding="utf-8",errors="replace")
                    self.assertEqual(result.returncode,0,result.stdout+result.stderr)  # 预处理错误同样必须失败。
                    self.assertRegex(result.stdout,rf"upscaleEnabled\s*=\s*{str(enabled).lower()}\s*;")  # 不仅检查宏名字存在，还检查真正的分支结果。
