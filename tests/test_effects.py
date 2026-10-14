"""第一波效果回归：只检查选项接入与展开后的算法骨架，不宣称像素效果。

示例 python -m unittest discover -s tests；全部使用离线展开，不建立显卡上下文。
"""
import unittest  # 保留标准测试入口。
import build  # 读取真实展开源码与原生选项。

class EffectTests(unittest.TestCase):
    """逐个效果核对选项单源、算法接入和默认路径。"""
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

    def test_horizon_ao_is_selectable_and_expands(self):
        """地平线环境遮蔽通过算法选项接入合成，螺旋路径仍然保留。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_AO_MODE",found); self.assertEqual(found["OMNI_AO_MODE"].values,("0","1"))  # 两种遮蔽算法可选。
        text = (build.SHADERS/"effects/ambient.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniHorizonOcclusion",text)  # 地平线积分独立成函数。
        self.assertIn("float omniSpiralOcclusion",text)  # 旧螺旋路径没有被删除。
        self.assertIn("omniHorizonCosine",text)  # 每方向地平线搜索独立成函数。
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
        text = (build.SHADERS/"effects/cloud.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniCloudShadow",text)  # 云影独立成函数。
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

    def test_reflection_denoise_filters_by_depth(self):
        """反射去噪按命中深度加权邻点，旧五点路径仍可保留。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_REFLECTION_DENOISE",found); self.assertEqual(found["OMNI_REFLECTION_DENOISE"].values,("0","1"))  # 去噪可开关。
        text = (build.SHADERS/"effects/reflection.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniReflectionFilter",text)  # 去噪独立成函数。
        self.assertIn("omniReflectionFilter(hitUv,target.z,roughness)",text)  # 使用命中深度做相似度判断。
        self.assertIn("OMNI_REFLECTION_DENOISE == 1",text)  # 旧路径由选项分派保留。

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
        self.assertIn("omniWaterHeight(p+vec2(0.08,0),world.y)",text)  # 有限差分包含细节。

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

    def test_climate_snow_and_wet(self):
        """气候温度按高度与噪声估计，驱动自然积雪与湿润且可回退手动值。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_CLIMATE",found); self.assertEqual(found["OMNI_CLIMATE"].values,("0","1"))  # 气候覆盖可开关。
        text = (build.SHADERS/"effects/material.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniTemperature",text)  # 温度估计独立成函数。
        self.assertIn("smoothstep(0.30,0.10,temperature)",text)  # 冷处自然积雪。
        self.assertIn("wetness*(0.5+0.5*(1.0-temperature))",text)  # 温度影响积水。
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

    def test_edge_adaptive_upscale_is_optional(self):
        """边缘自适应重采样作为最终显示前的可选滤波，默认关闭保持原行为。"""
        found,_,_ = build.configuration()
        self.assertEqual(found["OMNI_UPSCALE"].values,("false","true"))  # 上采样为开关选项。
        text = (build.SHADERS/"effects/upscale.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniUpscale",text)  # 重采样独立成函数。
        self.assertIn("mix(color,sum/weight,strength)",text)  # 平坦区收敛为原颜色。
        source = build.expand(build.SHADERS/"world0/final.fsh")  # 从最终显示入口展开。
        self.assertIn("omniUpscale",source)  # 最终显示包含可选重采样。
