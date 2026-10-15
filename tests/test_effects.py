"""效果回归：检查选项接入、预处理分支与算法边界，不宣称像素效果。

示例 python -m unittest discover -s tests；全部使用离线展开，不建立显卡上下文。
"""
import unittest  # 保留标准测试入口。
import json  # 读取显式绘制流程表。
import re  # 从实际公式提取固定阈值，拒绝未定义的顺序。
import subprocess  # 用真实预处理器验证开关分支。
import tempfile  # 探针源码只写入临时目录。
from pathlib import Path  # 临时阶段文件交给项目编译器。
import build  # 读取真实展开源码与原生选项。
import options  # 核对菜单分类覆盖。

class EffectTests(unittest.TestCase):
    """逐个效果核对选项单源、算法接入和默认路径。"""
    def test_fixed_smoothstep_edges_are_ordered(self):
        """固定阈值必须严格递增，避免驱动自行解释未定义计算。"""
        for path in (build.SHADERS/"effects").glob("*.glsl"):
            text = path.read_text(encoding="utf-8")  # 只检查自有效果，不改第三方源码。
            for match in re.finditer(r"smoothstep\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,", text):
                with self.subTest(path=path.name, formula=match[0]):  # 失败直接指出公式所在文件。
                    self.assertLess(float(match[1]),float(match[2]))  # 相等或反序都不受语言保证。

    def test_highlight_rolloff_is_adjustable(self):
        """高光压缩方式可选，并按强度在最保守曲线与所选曲线之间插值。"""
        found,_,_ = build.configuration()  # 原生定义仍是唯一默认值来源。
        self.assertIn("OMNI_TONEMAP_STRENGTH",found)  # 高光还原强度可调。
        self.assertIn("OMNI_TONEMAP_MODE",found)  # 压缩方式可选。
        self.assertEqual(found["OMNI_TONEMAP_MODE"].values,("0","1","2","3"))  # 四种方式。
        text = (build.SHADERS/"effects/color.glsl").read_text(encoding="utf-8")
        for name in ("omniToneMapAgx","omniToneMapAces","omniToneMapFilmic","omniToneMapSimple","omniToneMapOperator"):
            self.assertIn(name,text)  # 四种曲线与选择函数都在。
        self.assertIn("mix(omniToneMapSimple(color), omniToneMapOperator(color), OMNI_TONEMAP_STRENGTH)",text)  # 由强度统一插值。
        self.assertIn("pow(clamp(color,0.0,1.0),vec3(1.0/clamp(OMNI_GAMMA,1.0,4.0)))",text)  # 显示伽马可调。
        source = build.expand(build.SHADERS/"world0/final.fsh")  # 从加载器实际入口展开。
        self.assertIn("omniToneMap",source)  # 最终显示包含高光压缩。

    def test_ordered_dither_applies_before_clamp(self):
        """有序抖动在显示编码之后打散色带，选项可关闭。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_DITHER",found); self.assertEqual(found["OMNI_DITHER"].values,("0","1"))  # 默认与关闭值来自原生定义。
        text = (build.SHADERS/"effects/color.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniBayer",text)  # 有序矩阵阈值独立成函数。
        self.assertIn("pow(clamp(color,0.0,1.0),vec3(1.0/clamp(OMNI_GAMMA,1.0,4.0)))",text)  # 抖动发生在显示伽马之后。
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

    def test_exposure_target_and_speed_are_adjustable(self):
        """自动曝光的目标亮度与适应速度都是可调参数，替换原先写死的数值。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_EXPOSURE_TARGET",found); self.assertIn("OMNI_EXPOSURE_SPEED",found)  # 两个参数由调色源码定义。
        text = (build.SHADERS/"effects/color.glsl").read_text(encoding="utf-8")
        self.assertIn("OMNI_EXPOSURE_TARGET/exp",text)  # 目标亮度参与目标曝光。
        self.assertIn("*OMNI_EXPOSURE_SPEED",text)  # 适应速度参与混合。

    def test_corner_darkening_and_bounce_are_adjustable(self):
        """缝隙变暗只保留一套地平线做法，物体反光强度与范围可调。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_SSAO",found)  # 缝隙变暗开关。
        self.assertNotIn("OMNI_AO_MODE",found)  # 遮蔽算法选择已去掉。
        text = (build.SHADERS/"effects/ambient.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniHorizonOcclusion",text)  # 地平线积分独立成函数。
        self.assertNotIn("omniSpiralOcclusion",text)  # 旧螺旋算法已删除。
        self.assertIn("vec2 omniHorizon",text)  # 每方向地平线搜索独立成函数，并返回有效标记。
        self.assertIn("if (!found) return 0.0;",text)  # 无有效邻点时这一片不得当成最大遮挡。
        self.assertIn("OMNI_AO_STRENGTH",found); self.assertIn("OMNI_BOUNCE_STRENGTH",found)  # 变暗与反光强度可调。
        self.assertIn("*OMNI_AO_STRENGTH",text)  # 变暗强度参与遮挡系数。
        self.assertIn("*OMNI_BOUNCE_STRENGTH",text)  # 反光强度参与反光叠加。
        self.assertIn("OMNI_AO_SLICES",found); self.assertIn("OMNI_AO_STEPS",found)  # 变暗方向数与精细度可调。
        self.assertIn("OMNI_BOUNCE_RADIUS",found)  # 物体反光范围可调。
        self.assertIn("const int steps = OMNI_AO_STEPS",text)  # 步数来自选项。
        self.assertIn("const int slices = OMNI_AO_SLICES",text)  # 方向数来自选项。
        self.assertIn("omniBounceRadius",text)  # 反光用自己的范围。
        source = build.expand(build.SHADERS/"world0/composite.fsh")  # 从实际合成入口展开全部引用。
        self.assertIn("omniHorizonOcclusion",source)  # 合成阶段包含缝隙变暗。

    def test_lens_flare_uses_scene_highlight(self):
        """镜头耀斑在最终显示叠加，光源强度取自现有亮部且可关闭。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_LENS_FLARE",found); self.assertEqual(found["OMNI_LENS_FLARE"].values,("0","1"))  # 耀斑可开关。
        text = (build.SHADERS/"effects/lens.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniLensFlare",text)  # 耀斑独立成函数。
        self.assertIn("bool omniSunScreen",text)  # 屏幕太阳位置独立成函数。
        for name in ("OMNI_DOF_STRENGTH","OMNI_MOTION_BLUR_STRENGTH","OMNI_FLARE_STRENGTH"):
            self.assertIn(name,found)  # 景深、运动模糊与耀斑强度都是可调参数。
        self.assertIn("*OMNI_DOF_STRENGTH",text)  # 景深强度参与弥散半径。
        self.assertIn("*OMNI_MOTION_BLUR_STRENGTH",text)  # 运动模糊强度参与屏幕位移。
        self.assertIn("*OMNI_FLARE_STRENGTH",text)  # 耀斑强度参与合成。
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
        self.assertIn("OMNI_CLOUD_STEPS",found)  # 体积云步数是独立可调参数。
        self.assertIn("OMNI_CLOUD_BRIGHTNESS",found)  # 云亮度是独立可调参数。
        self.assertIn("OMNI_CLOUD_SHADOW_STRENGTH",found)  # 云影浓淡是独立可调参数。
        text = (build.SHADERS/"effects/cloud.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniCloudShadow",text)  # 云影独立成函数。
        self.assertIn("OMNI_CLOUD_SHADOW_STRENGTH",text)  # 云影浓淡参与光学厚度。
        self.assertIn("omniCloudDensity(p)",text)  # 复用同一云密度来源。
        self.assertIn("smoothstep(0.0,0.2,height)",text)  # 云影与可见云共用同一套上下边缘渐薄。
        self.assertIn("stepMeters",text)  # 云影按米累积光学厚度，与可见云同一消光口径。
        sun = (build.SHADERS/"effects/sunlight.glsl").read_text(encoding="utf-8")
        self.assertIn("omniCloudShadow(world)",sun)  # 直射光按云影衰减。
        source = build.expand(build.SHADERS/"world0/gbuffers_terrain.fsh")  # 从地形入口展开。
        self.assertIn("omniCloudShadow",source)  # 地形照明包含云影。

    def test_cloud_has_two_selectable_styles(self):
        """云提供体积与平面两种做法，可切换，且平面云复用同一套颜色与银边。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_CLOUD_MODE",found)  # 做法可切换。
        self.assertEqual(found["OMNI_CLOUD_MODE"].values,("0","1"))  # 体积与平面两档。
        text = (build.SHADERS/"effects/cloud.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniCloud",text)  # 云入口保留。
        self.assertIn("OMNI_CLOUD_STEPS",text)  # 采样步数是可调参数。
        self.assertIn("omniPlanarCloud",text)  # 平面云做法存在。
        self.assertIn("omniPlanarDensity",text)  # 平面云密度独立成函数。
        self.assertIn("OMNI_CLOUD_MODE == 1",text)  # 入口按做法分派。
        source = build.expand(build.SHADERS/"world0/composite.fsh")  # 从合成入口展开。
        self.assertIn("omniPlanarCloud",source)  # 合成阶段能取到平面云做法。

    def test_cloud_base_outscatter_fade_and_noise(self):
        """云底亮度、外散射、淡出距离与噪声尺度都是可调参数并参与计算。"""
        found,_,_ = build.configuration()
        for name in ("OMNI_CLOUD_BOTTOM","OMNI_CLOUD_OUTSCATTER","OMNI_CLOUD_FADE","OMNI_CLOUD_NOISE_SCALE"):
            self.assertIn(name,found)  # 每个参数由云源码定义。
        text = (build.SHADERS/"effects/cloud.glsl").read_text(encoding="utf-8")
        self.assertIn("dayColor*OMNI_CLOUD_BOTTOM",text)  # 云底亮度参与颜色下限。
        self.assertIn("pow(facing,OMNI_CLOUD_OUTSCATTER)",text)  # 外散射参与银边指数。
        self.assertIn("smoothstep(far*0.5,far,",text)  # 淡出距离参与可见度。
        self.assertIn("*OMNI_CLOUD_NOISE_SCALE",text)  # 噪声尺度参与碎边频率。
        source = build.expand(build.SHADERS/"world0/composite.fsh")  # 从合成入口展开。
        self.assertIn("OMNI_CLOUD_FADE",source)  # 合成阶段能取到淡出距离。

    def test_cloud_weather_sets_and_lighting(self):
        """云在晴天与雨天各有一套覆盖/厚度/密度/尺度/受光，按湿润度切换。"""
        found,_,_ = build.configuration()
        for name in ("OMNI_CLOUD_DENSITY","OMNI_CLOUD_SUNLIGHT","OMNI_CLOUD_SKYLIGHT",
                     "OMNI_CLOUD_RAIN_COVERAGE","OMNI_CLOUD_RAIN_THICKNESS","OMNI_CLOUD_RAIN_DENSITY",
                     "OMNI_CLOUD_RAIN_SCALE","OMNI_CLOUD_RAIN_SUNLIGHT","OMNI_CLOUD_RAIN_SKYLIGHT"):
            self.assertIn(name,found)  # 每个晴雨参数都由云源码定义。
        text = (build.SHADERS/"effects/cloud.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniCloudWeather",text)  # 晴雨切换独立成函数。
        self.assertIn("mix(OMNI_CLOUD_COVERAGE,OMNI_CLOUD_RAIN_COVERAGE,omniCloudWeather())",text)  # 云量按天气插值。
        self.assertIn("mix(OMNI_CLOUD_SUNLIGHT,OMNI_CLOUD_RAIN_SUNLIGHT,omniCloudWeather())",text)  # 受光按天气插值。
        self.assertIn("*omniCloudDensityMul()",text)  # 密度倍率参与消光。
        self.assertIn("*omniCloudThickness()",text)  # 厚度按天气切换并参与光程。
        source = build.expand(build.SHADERS/"world0/composite.fsh")  # 从合成入口展开。
        self.assertIn("omniCloudWeather",source)  # 合成阶段包含晴雨切换。

    def test_underwater_volumetric_shafts(self):
        """水下体积光沿视线步进阴影，接入合成雾且可关闭。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_UNDERWATER_FOG",found); self.assertEqual(found["OMNI_UNDERWATER_FOG"].values,("0","1"))  # 水下光柱可开关。
        text = (build.SHADERS/"effects/fog.glsl").read_text(encoding="utf-8")
        self.assertIn("isEyeInWater == 1",text)  # 只有水下才执行光柱。
        self.assertIn("omniShadow(sampleWorld,sampleNormal)",text)  # 光柱来自真实阴影可见性。
        self.assertIn("OMNI_VFOG_STEPS",found)  # 体积光步数可调。
        source = build.expand(build.SHADERS/"world0/composite.fsh")  # 从实际合成入口展开。
        self.assertIn("vec3 omniFog",source)  # 合成阶段包含雾主体。

    def test_fog_parameters_are_adjustable(self):
        """雾的开关、浓度、颜色与各维度、水下参数都可调。"""
        found,_,_ = build.configuration()
        for name in ("OMNI_FOG_ENABLED","OMNI_FOG_DENSITY","OMNI_FOG_TINT","OMNI_HEIGHT_FOG_ENABLED",
                     "OMNI_HEIGHT_FOG","OMNI_FOG_HEIGHT","OMNI_FOG_SCALE","OMNI_VOLUMETRIC_STRENGTH",
                     "OMNI_UNDERWATER_STRENGTH","OMNI_UNDERWATER_DENSITY","OMNI_UNDERWATER_TINT",
                     "OMNI_END_FOG_DENSITY","OMNI_NETHER_FOG_DENSITY"):
            self.assertIn(name,found)  # 每个参数由雾源码定义。
        text = (build.SHADERS/"effects/fog.glsl").read_text(encoding="utf-8")
        self.assertIn("- OMNI_FOG_HEIGHT",text)  # 起始高度参与密度计算。
        self.assertIn("*OMNI_FOG_SCALE)",text)  # 衰减参与密度计算。
        self.assertIn("OMNI_FOG_TINT",text)  # 雾颜色参与着色。
        self.assertIn("*OMNI_UNDERWATER_DENSITY",text)  # 水下浓度参与吸收。
        self.assertIn("OMNI_UNDERWATER_TINT",text)  # 水下颜色参与着色。
        self.assertIn("*OMNI_END_FOG_DENSITY",text)  # 末地雾浓度参与密度。
        self.assertIn("*OMNI_NETHER_FOG_DENSITY",text)  # 下界雾浓度参与密度。

    def test_reflection_denoise_filters_by_depth(self):
        """反射去噪按命中深度加权邻点，旧五点路径仍可保留。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_REFLECTION_DENOISE",found); self.assertEqual(found["OMNI_REFLECTION_DENOISE"].values,("0","1"))  # 去噪可开关。
        text = (build.SHADERS/"effects/reflection.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniReflectionFilter",text)  # 去噪独立成函数。
        self.assertIn("omniReflectionFilter(hitUv,target.z,roughness)",text)  # 使用命中深度做相似度判断。
        self.assertIn("OMNI_REFLECTION_DENOISE == 1",text)  # 旧路径由选项分派保留。
        self.assertIn("OMNI_REFLECTION_BLUR",found)  # 反射模糊半径可调。
        self.assertIn("*OMNI_REFLECTION_BLUR",text)  # 模糊半径参与计算。

    def test_reflection_fallback_uses_full_sky(self):
        """屏幕外反射回退复用天空、云与氛围的同一套合成，并可单独关闭天空反射。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_SKY_REFLECTION",found)  # 天空反射开关。
        text = (build.SHADERS/"effects/reflection.glsl").read_text(encoding="utf-8")
        self.assertIn("omniAtmosphere(omniCloud(omniSky(skyDirection)",text)  # 回退色与背景天空一致。
        self.assertIn("OMNI_SKY_REFLECTION==1 ?",text)  # 关闭天空反射时回退为零。
        self.assertIn('#include "/effects/cloud.glsl"',text)  # 反射确实引入了云。
        self.assertIn('#include "/effects/atmosphere.glsl"',text)  # 反射确实引入了氛围。

    def test_sky_parameters_are_adjustable(self):
        """日月大小与色温、星星数量、日落颜色、天空亮度、末地天空亮度都可调。"""
        found,_,_ = build.configuration()
        for name in ("OMNI_SUN_DISK","OMNI_SUN_SIZE","OMNI_MOON_DISK","OMNI_MOON_SIZE","OMNI_CELESTIAL_TINT",
                     "OMNI_STAR_STRENGTH","OMNI_STAR_DENSITY","OMNI_SUNSET_STRENGTH","OMNI_SUNSET_TINT",
                     "OMNI_SKY_SATURATION","OMNI_SKY_BRIGHTNESS","OMNI_END_SKY_BRIGHTNESS"):
            self.assertIn(name,found)  # 每个参数都由天空源码定义。
        text = (build.SHADERS/"effects/sky.glsl").read_text(encoding="utf-8")
        self.assertIn("OMNI_SUN_SIZE",text)  # 太阳大小参与圆盘阈值。
        self.assertIn("OMNI_MOON_SIZE",text)  # 月亮大小参与圆盘阈值。
        self.assertIn("celestialTint",text)  # 日月色温参与圆盘着色。
        self.assertIn("OMNI_STAR_DENSITY",text)  # 星星数量参与阈值。
        self.assertIn("OMNI_SUNSET_TINT",text)  # 日落颜色参与着色。
        self.assertIn("*= OMNI_SKY_BRIGHTNESS",text)  # 天空整体亮度参与着色。
        self.assertIn("* OMNI_END_SKY_BRIGHTNESS",text)  # 末地天空亮度参与着色。

    def test_atmosphere_strengths_are_adjustable(self):
        """极光、彩虹、散射与闪电强度都是可调参数，替换原先写死的倍率。"""
        found,_,_ = build.configuration()
        for name in ("OMNI_AURORA_STRENGTH","OMNI_RAINBOW_STRENGTH","OMNI_SCATTER_STRENGTH","OMNI_LIGHTNING_STRENGTH"):
            self.assertIn(name,found)  # 每个参数都由氛围或天空源码定义。
        text = (build.SHADERS/"effects/atmosphere.glsl").read_text(encoding="utf-8")
        self.assertIn("*OMNI_AURORA_STRENGTH",text)  # 极光强度参与着色。
        self.assertIn("*OMNI_RAINBOW_STRENGTH",text)  # 彩虹强度参与着色。
        self.assertIn("*OMNI_LIGHTNING_STRENGTH",text)  # 闪电强度参与着色。
        sky = (build.SHADERS/"effects/sky.glsl").read_text(encoding="utf-8")  # 散射强度随物理模型一起移到天空源码。
        self.assertIn("*OMNI_SCATTER_STRENGTH",sky)  # 散射强度参与大气散射亮度。

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
        """物理大气散射在天空源码里独立实现，不依赖外部查找表。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_ATMOSPHERE_SCATTER",found); self.assertEqual(found["OMNI_ATMOSPHERE_SCATTER"].values,("0","1"))  # 散射可开关。
        for name in ("OMNI_ATMOSPHERE_STEPS","OMNI_ATMOSPHERE_MIE_G","OMNI_ATMOSPHERE_OZONE","OMNI_ATMOSPHERE_MULTIPLE"):
            self.assertIn(name,found)  # 精细度、方向性、臭氧与多次散射各有选项。
        text = (build.SHADERS/"effects/sky.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniAtmosphereSky",text)  # 大气散射独立成函数。
        self.assertIn("omniAtmosphereSky(d,sun)",text)  # 天空阶段调用散射。
        self.assertIn("omniSunTransmittance",text)  # 计算太阳方向透过率。
        self.assertIn("omniOzoneDensity",text)  # 含臭氧吸收剖面。
        source = build.expand(build.SHADERS/"world0/composite.fsh")  # 从实际合成入口展开。
        self.assertIn("omniAtmosphereSky",source)  # 合成阶段包含大气散射。

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
        distant = (build.SHADERS/"rendering/distant.glsl").read_text(encoding="utf-8")
        self.assertIn("DH_BLOCK_WATER && viewNormal.y>0.9",distant)  # 远景顶面水也按同一海浪抬升。
        self.assertIn("omniOceanHeight((waterWorld+cameraPosition).xz)",distant)  # 与近景共用同一高度函数。

    def test_water_optics_are_adjustable(self):
        """水体吸收、散射与波速都是可调参数，且共用同一份光学常数。"""
        found,_,_ = build.configuration()
        for name in ("OMNI_WATER_ABSORB_R","OMNI_WATER_ABSORB_G","OMNI_WATER_ABSORB_B",
                     "OMNI_WATER_SCATTER_R","OMNI_WATER_SCATTER_G","OMNI_WATER_SCATTER_B","OMNI_WAVE_SPEED","OMNI_WAVE_SCALE","OMNI_REFRACTION_STRENGTH","OMNI_RIPPLE_STRENGTH","OMNI_WATER_GLINT","OMNI_WATER_BUMP_STRENGTH","OMNI_OCEAN_HEIGHT","OMNI_WATER_CLEAR"):
            self.assertIn(name,found)  # 每个参数都由效果源码定义。
        water = (build.SHADERS/"effects/water.glsl").read_text(encoding="utf-8")
        self.assertIn("OMNI_WATER_GLINT * smoothstep",water)  # 阳光高光只在白天出现。
        self.assertIn("const vec3 omniWaterAbsorbance = vec3(OMNI_WATER_ABSORB_R",water)  # 吸收只由选项组成一处向量。
        self.assertIn("omniWaterTransmit",water)  # 吸收与散射共用一个函数。
        fog = (build.SHADERS/"effects/fog.glsl").read_text(encoding="utf-8")
        self.assertIn("omniWaterTransmit(color,distance*OMNI_UNDERWATER_DENSITY)",fog)  # 水下雾复用同一份水体光学常数，并按浓度缩放距离。

    def test_climate_snow_and_wet(self):
        """气候温度按高度与噪声估计，驱动自然积雪与湿润且可回退手动值。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_CLIMATE_SNOW",found); self.assertEqual(found["OMNI_CLIMATE_SNOW"].values,("0","1"))  # 气候覆盖可开关。
        text = (build.SHADERS/"effects/material.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniTemperature",text)  # 温度估计独立成函数。
        self.assertIn("1.0-smoothstep(0.10,0.30,temperature)",text)  # 正序插值后取反，冷处积雪且不触发未定义计算。
        self.assertIn("wetness*(0.5+0.5*temperature)",text)  # 暖处湿润权重更高，与菜单说明一致。
        self.assertIn("OMNI_CLIMATE_SNOW == 1",text)  # 手动回退路径由选项分派保留。
        source = build.expand(build.SHADERS/"world0/gbuffers_terrain.fsh")  # 从地形入口展开。
        self.assertIn("omniTemperature",source)  # 地形表面包含气候覆盖。
        for name in ("OMNI_WET_STRENGTH","OMNI_SNOW_STRENGTH"):
            self.assertIn(name,found)  # 湿润与积雪强度都是可调参数。
        self.assertIn("* OMNI_WET_STRENGTH",text)  # 湿润强度参与湿润量。
        self.assertIn("OMNI_SNOW*OMNI_SNOW_STRENGTH",text)  # 积雪强度参与覆盖量。

    def test_ggx_specular_highlight(self):
        """镜面高光用 GGX 分布接入直接光，材质粗糙度与金属来自表面参数。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_SPECULAR",found); self.assertEqual(found["OMNI_SPECULAR"].values,("0","1"))  # 镜面可开关。
        text = (build.SHADERS/"effects/sunlight.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniSpecular",text)  # 镜面独立成函数。
        self.assertIn("omniSpecular(albedo,normal,world,materialParams,sun,shadow)",text)  # 直接光叠加镜面。
        self.assertIn("vec3 f0 = mix(vec3(clamp(materialParams.y,0.0,1.0)),clamp(albedo,0.0,1.0),metal);",text)  # 反射率口径与屏幕反射一致：非金属读材质反射率，金属用底色。
        self.assertIn("return albedo * lightColor + specular +",text)  # 高光单独相加，不再被底色乘暗或染色。
        reflection = (build.SHADERS/"effects/reflection.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 f0 = mix(vec3(materialParams.y),clamp(color,0.0,1.0),metal);",reflection)  # 两处使用同一种反射率口径。
        self.assertIn("materialParams",text)  # 材质参数进入光照。
        source = build.expand(build.SHADERS/"world0/gbuffers_terrain.fsh")  # 从地形入口展开。
        self.assertIn("omniSpecular",source)  # 地形光照包含镜面高光。

    def test_light_color_temperature_is_adjustable(self):
        """阳光、环境光、火把光色温与火把光、手持光强度都是可调参数，默认等于原行为。"""
        found,_,_ = build.configuration()
        for name in ("OMNI_SUN_TINT","OMNI_AMBIENT_TINT","OMNI_BLOCKLIGHT_TINT","OMNI_BLOCKLIGHT_STRENGTH","OMNI_HELD_BRIGHTNESS"):
            self.assertIn(name,found)  # 每个参数由光照源码定义。
        self.assertEqual(found["OMNI_SUN_TINT"].default,"0.0")  # 默认中性，不改变现有画面。
        self.assertEqual(found["OMNI_BLOCKLIGHT_STRENGTH"].default,"1.0")  # 默认强度不改变现有画面。
        text = (build.SHADERS/"effects/sunlight.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniTint",text)  # 色温换算独立成函数。
        self.assertIn("omniTint(OMNI_SUN_TINT)",text)  # 直射光应用色温。
        self.assertIn("omniTint(OMNI_AMBIENT_TINT)",text)  # 环境光应用色温。
        self.assertIn("omniTint(OMNI_BLOCKLIGHT_TINT)",text)  # 方块光应用色温。
        self.assertIn("* OMNI_BLOCKLIGHT_STRENGTH",text)  # 方块光强度参与照明。
        self.assertIn("* OMNI_HELD_BRIGHTNESS",text)  # 手持光亮度参与照明。

    def test_lightweight_preset_disables_heavy_effects(self):
        """轻量预设关闭阴影、高光、气候、云影与水面细节等较重的默认效果。"""
        _, profiles, _ = build.configuration()
        lightweight = next(profile for profile in profiles if profile.name == "lightweight")  # 找到轻量预设。
        for name in ("OMNI_SHADOW_ENABLED","OMNI_SSAO","OMNI_SSR","OMNI_SPECULAR","OMNI_CLIMATE_SNOW",
                     "OMNI_CLOUD_SHADOW","OMNI_WATER_BUMP","OMNI_OCEAN_WAVES","OMNI_UNDERWATER_FOG",
                     "OMNI_END_FOG","OMNI_LENS_FLARE","OMNI_VEGETATION_WIND","OMNI_RAIN_RIPPLES"):
            self.assertIn(lightweight.values[name],("false","0"),name)  # 每个较重的效果在轻量预设里都被关闭。

    def test_edge_adaptive_upscale_is_optional(self):
        """边缘自适应重采样作为最终显示前的可选滤波，默认关闭保持原行为。"""
        found,_,_ = build.configuration()
        self.assertEqual(found["OMNI_UPSCALE"].values,("false","true"))  # 上采样为开关选项。
        self.assertEqual(found["OMNI_UPSCALE"].default,"false")  # 默认关闭，不由文件保护宏偷偷启用。
        text = (build.SHADERS/"effects/upscale.glsl").read_text(encoding="utf-8")
        self.assertFalse(any(line.strip() == "#define OMNI_UPSCALE" for line in text.splitlines()))  # 检查未替换选项的原始源码，避免离线配置掩盖重名。
        self.assertIn("vec3 omniUpscale",text)  # 重采样独立成函数。
        self.assertIn("mix(color,sum/weight,strength)",text)  # 平坦区收敛为原颜色。
        self.assertIn("OMNI_UPSCALE_STRENGTH",found)  # 超分强度可调。
        self.assertIn("*OMNI_UPSCALE_STRENGTH",text)  # 强度参与混合权重。
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

    def test_season_shifts_grass_and_leaves(self):
        """季节按顶点里的群系染色识别植被并随世界天数上色，接入地形底色且默认关闭。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_SEASONS",found); self.assertEqual(found["OMNI_SEASONS"].default,"false")  # 默认关闭。
        self.assertIn("OMNI_SEASON_TINT",found)  # 季节颜色由季节源码定义。
        text = (build.SHADERS/"effects/season.glsl").read_text(encoding="utf-8")
        self.assertIn("float omniFoliage",text)  # 植被程度独立成函数。
        self.assertIn("vertexColor.g - max(vertexColor.r, vertexColor.b)",text)  # 绿色比红蓝多才算植被，白色方块与偏蓝的水都排除。
        self.assertNotIn("materialId",text)  # 不再靠方块编号，草方块顶面也会一起变色。
        self.assertIn("float(worldDay)",text)  # 相位来自世界天数。
        source = build.expand(build.SHADERS/"world0/gbuffers_terrain.fsh")  # 从地形入口展开。
        self.assertIn("omniSeason(albedo,tint.rgb)",source)  # 地形底色按顶点色接入季节。

    def test_weather_darkening_and_seam_fog_are_local(self):
        """雨天变暗只作用露天处；远景雾衔接只在近景渲染距离附近补一圈。"""
        weather = (build.SHADERS/"effects/weather.glsl").read_text(encoding="utf-8")
        self.assertIn("eyeBrightnessSmooth.y",weather)  # 按头顶天空光决定变暗程度，洞里不变暗。
        fog = (build.SHADERS/"effects/fog.glsl").read_text(encoding="utf-8")
        self.assertIn("(1.0-smoothstep(far,far*1.4,distance))",fog)  # 雾衔接在交界外侧收回，不把整片远景盖住。

    def test_entity_light_and_hand_size_are_adjustable(self):
        """生物受光强度、色温与手持物大小都可调，分别接入实体光照与手持物顶点。"""
        found,_,_ = build.configuration()
        for name in ("OMNI_ENTITY_LIGHT","OMNI_ENTITY_TINT","OMNI_HAND_FOV"):
            self.assertIn(name,found)  # 每个参数由生物源码定义。
        text = (build.SHADERS/"effects/entity.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniEntityLight",text)  # 生物受光独立成函数。
        self.assertIn("vec4 omniHandZoom",text)  # 手持物缩放独立成函数。
        self.assertIn("OMNI_ENTITY_TINT",text)  # 色温参与生物受光。
        self.assertIn("OMNI_HAND_FOV",text)  # 视野参与手持物缩放。
        self.assertIn("tan(radians(35.0)) / tan(radians(",text)  # 缩放按半视野角正切之比计算，等价于真实改视野。
        entities = build.expand(build.SHADERS/"world0/gbuffers_entities.fsh")  # 从实体入口展开。
        self.assertIn("omniEntityLight",entities)  # 实体光照包含生物受光。
        hand = build.expand(build.SHADERS/"world0/gbuffers_hand.vsh")  # 从手持物顶点入口展开。
        self.assertIn("omniHandZoom",hand)  # 手持物顶点包含缩放。
        terrain = (build.SHADERS/"rendering/terrain.glsl").read_text(encoding="utf-8")
        self.assertIn("#if defined OMNI_ENTITIES && !defined OMNI_BLOCK_ENTITY",terrain)  # 箱子这类方块实体不受生物受光影响。
        programs = json.loads((build.SHADERS/"rendering/programs.json").read_text(encoding="utf-8"))["programs"]
        self.assertIn("OMNI_BLOCK_ENTITY",programs["gbuffers_block"])  # 方块实体程序带独立标记。
        self.assertNotIn("OMNI_BLOCK_ENTITY",programs["gbuffers_entities"])  # 生物程序不带。

    def test_player_glow_blends_glowing_entities(self):
        """发光实体用独立宏，按玩家发光遮盖在普通受光与自身发光色之间插值。"""
        programs = json.loads((build.SHADERS/"rendering/programs.json").read_text(encoding="utf-8"))["programs"]
        self.assertIn("OMNI_GLOWING",programs["gbuffers_entities_glowing"])  # 发光实体单独识别。
        self.assertNotIn("OMNI_EMISSIVE",programs["gbuffers_entities_glowing"])  # 不再被当成固定自发光。
        source = build.expand(build.SHADERS/"world0/gbuffers_entities_glowing.fsh")
        self.assertIn("lit=omniGlow(lit,albedo)",source)  # 发光实体入口包含发光插值。

    def test_weather_particles_use_alpha_and_vertex_slant(self):
        """雨雪可见度缩放透明度，斜度在顶点阶段推移几何，雨雪按群系降水类型区分。"""
        terrain = (build.SHADERS/"rendering/terrain.glsl").read_text(encoding="utf-8")
        self.assertIn("s.base.a=clamp(s.base.a*omniWeatherVisibility(),0.0,1.0)",terrain)  # 缩放透明度，取零会被丢弃而不是变黑。
        self.assertIn("omniRainSlant(omniWorld(view.xyz))",terrain)  # 斜度在世界空间推移顶点。
        weather = (build.SHADERS/"effects/weather.glsl").read_text(encoding="utf-8")
        self.assertIn("biome_precipitation == 2",weather)  # 雪由加载器给的降水类型判断。
        self.assertIn("#ifndef OMNI_WEATHER_INCLUDED",weather)  # 引入标记不与程序宏同名。
        vertex = build.expand(build.SHADERS/"world0/gbuffers_weather.vsh")
        self.assertIn("#define OMNI_WEATHER_PASS",vertex)  # 雨雪程序使用独立的程序宏。
        water = (build.SHADERS/"effects/water.glsl").read_text(encoding="utf-8")
        self.assertIn("if (grid > 0.0)",water)  # 落点密度取零时不除以零。

    def test_resource_sky_keeps_textures_under_clouds(self):
        """资源包天空：选项决定加载器是否画日月贴图，延迟阶段把贴图叠在天空上、云下面。"""
        _,_,files = build.configuration()
        menu = files[build.SHADERS/"shaders.properties"]
        self.assertIn("#ifdef OMNI_RESOURCE_SKY\n",menu)  # 绘制设置按选项挑选分支。
        self.assertIn("sky = false",menu)  # 原版天空几何关闭，天空像素只剩贴图。
        buffers = (build.SHADERS/"rendering/buffers.glsl").read_text(encoding="utf-8")
        self.assertIn("const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);",buffers)  # 零号画面清成黑色，不把雾色叠进去。
        lighting = (build.SHADERS/"rendering/lighting.glsl").read_text(encoding="utf-8")
        self.assertIn("sky += textured;",lighting)  # 贴图叠在云之前。
        self.assertIn("omniCloud(sky,direction,32000.0)",lighting)  # 云在贴图之后合成，能挡住太阳。
        terrain = (build.SHADERS/"rendering/terrain.glsl").read_text(encoding="utf-8")
        self.assertIn("return omniLinear(s.base.rgb);",terrain)  # 贴图写成线性颜色。

    def test_render_scale_only_resizes_composite_buffer(self):
        """渲染缩放只改六号画面尺寸，合成阶段用全分辨率像素坐标读取其他画面。"""
        _,_,files = build.configuration()
        menu = files[build.SHADERS/"shaders.properties"]
        self.assertIn("#if OMNI_RENDER_SCALE == 50\n",menu)  # 半分辨率分支。
        self.assertIn("size.buffer.colortex6 = 0.5 0.5",menu)
        self.assertIn("size.buffer.colortex6 = 0.75 0.75",menu)
        self.assertNotIn("size.buffer.colortex0",menu)  # 几何写入的画面不能缩放。
        composite = (build.SHADERS/"rendering/composite.glsl").read_text(encoding="utf-8")
        self.assertNotIn("gl_FragCoord",composite)  # 合成阶段不用缩放后的片元坐标读画面。
        for path in build.SHADERS.rglob("*.glsl"):  # 六号画面缩放后只能按比例坐标采样。
            self.assertNotIn("texelFetch(colortex6",path.read_text(encoding="utf-8"),path.name)

    def test_distant_toggle_and_fog_blend(self):
        """远景开关决定远景是否走完整光照，远景雾衔接只在远景存在时补雾。"""
        distant = (build.SHADERS/"rendering/distant.glsl").read_text(encoding="utf-8")
        self.assertIn("#ifdef OMNI_DH_ENABLED",distant)  # 开关分出完整光照与基础路径。
        fog = (build.SHADERS/"effects/fog.glsl").read_text(encoding="utf-8")
        self.assertIn("OMNI_DH_FOG_BLEND",fog)  # 雾衔接参与雾量。

    def test_frame_time_bar_is_drawn_last(self):
        """性能计时在最终显示的最后一步叠加，只读整帧时间。"""
        debug = (build.SHADERS/"effects/debug.glsl").read_text(encoding="utf-8")
        self.assertIn("frameTime*1000.0",debug)  # 用加载器给的整帧时间换算毫秒。
        final = (build.SHADERS/"rendering/final.glsl").read_text(encoding="utf-8")
        self.assertIn("omniProfiler(debugColor(",final)  # 叠在调试视图之后。

    def test_include_guards_never_collide(self):
        """引入标记不能和程序宏或选项同名，否则定义了该宏的程序会整段跳过这个文件。"""
        found,_,_ = build.configuration()
        programs = json.loads((build.SHADERS/"rendering/programs.json").read_text(encoding="utf-8"))
        macros = {macro for flags in programs["programs"].values() for macro in flags[1:]}  # 每个程序额外定义的宏。
        macros |= {macro for macro in programs["dimensions"].values() if macro}  # 维度宏。
        for path in build.SHADERS.rglob("*.glsl"):
            match = re.search(r"#ifndef (\w+)\s*(?://[^\n]*)?\n#define \1\b",path.read_text(encoding="utf-8"))  # 文件开头的引入标记。
            if match:
                with self.subTest(path=path.name):
                    self.assertNotIn(match[1],macros)  # 和程序宏同名会让整段代码被跳过。
                    self.assertNotIn(match[1],found)  # 和选项同名会让玩家开关变成引入标记。

    def test_boolean_options_are_detected_by_condition(self):
        """布尔选项必须在某处按定义与未定义各判一次，否则加载器不认它，菜单项也就无法解析。"""
        found,_,_ = build.configuration()
        text = "\n".join(path.read_text(encoding="utf-8") for path in build.SHADERS.rglob("*") if path.suffix in (".glsl", ".vsh", ".fsh", ".csh"))
        for name, option in found.items():
            if option.values == ("false", "true"):
                with self.subTest(option=name):
                    self.assertRegex(text, r"#\s*(?:ifdef|ifndef)\s+" + re.escape(name) + r"\b")

    def test_const_vector_constructors_match_their_type(self):
        """加载器会解析 const 声明，vecN 构造函数必须给足分量个数；vec4(0.0) 这类简写会被拒绝并让整包加载失败。"""
        constructor = re.compile(r"const\s+(vec[234])\s+\w+\s*=\s*(vec[234])\(([^;]*)\)\s*;")
        for path in build.SHADERS.rglob("*"):
            if path.suffix not in (".glsl", ".vsh", ".fsh", ".csh"):
                continue
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                match = constructor.search(line)
                if not match or match[1] != match[2]:
                    continue
                arguments = [part for part in re.split(r",(?![^()]*\))", match[3]) if part.strip()]  # 只数顶层逗号分隔的参数。
                with self.subTest(path=path.name, line=number):
                    self.assertEqual(len(arguments), int(match[1][3]))

    def test_buffer_format_directives_are_bare_and_defined(self):
        """格式指令必须放在块注释里、每行只写指令本身：行尾带说明会让加载器读不到，自己定义格式名又会让它读到数字。"""
        text = (build.SHADERS/"rendering/buffers.glsl").read_text(encoding="utf-8")
        commented = re.sub(r"/\*.*?\*/", "", text, flags=re.S)  # 去掉块注释后，源码里不应再有格式指令。
        self.assertNotIn("Format", commented)  # 指令只在块注释里出现。
        for line in re.findall(r"^const int colortex\d+Format = [A-Z0-9_]+;$", text, re.M):
            self.assertRegex(line, r"^const int colortex\d+Format = [A-Z0-9_]+;$")  # 每行只写指令本身。
        self.assertRegex(text, r"const int colortex0Format = RGBA16F;")  # 指令带名字而不是数字。
        self.assertNotRegex(text, r"#define RGBA\d+F")  # 格式名交由加载器提供，包内不重复定义。

    def test_custom_images_feature_is_declared(self):
        """用自定义图像就必须声明能力开关，缺能力时 LPV 回退到屏幕空间间接光。"""
        settings = options.read_pipeline(build.SHADERS/"rendering/pipeline.properties")
        self.assertIn("CUSTOM_IMAGES",settings["iris.features.optional"])  # 声明为可选能力，缺少时仍能加载。
        self.assertIn("image.omniLpvA",settings)  # 自定义图像仍由绘制设置提供。
        fields = settings["image.omniLpvA"].split()  # 字段顺序与取值必须符合加载器要求。
        self.assertEqual(len(fields),9,fields)  # 采样器名加八个设置项。
        self.assertTrue(fields[1].islower() and fields[2].islower(),fields)  # 像素格式与图像格式用小写。
        self.assertIn(fields[3],("byte","short","int","float"),fields)  # 像素类型必须是加载器认识的一种。
        for name in ("effects/lpv.glsl","effects/ambient.glsl","rendering/lpv.glsl"):
            text = (build.SHADERS/name).read_text(encoding="utf-8")
            self.assertIn("IRIS_FEATURE_CUSTOM_IMAGES",text)  # 每处图像读写都按能力开关回退。

    def test_include_lines_are_bare_references(self):
        """任何一行出现 #include 都必须是干净的引用行：加载器在去注释之前扫描引用，注释里的示例会被当成本文件自我包含。"""
        references = re.compile(r'\s*#include\s+"[^"]+"\s*$')
        for path in build.SHADERS.rglob("*"):
            if path.suffix not in (".glsl", ".vsh", ".fsh", ".csh"):
                continue
            text = path.read_text(encoding="utf-8")
            text = re.sub(r"/\*.*?\*/", lambda match: "\n" * match.group(0).count("\n"), text, flags=re.S)  # 先挖掉块注释，块注释里的示例同样会被加载器扫到。
            for number, line in enumerate(text.splitlines(), 1):
                if "#include" in line and not references.fullmatch(line):
                    self.fail(f"{path.name}:{number} 含 #include 的行不是干净引用：{line.strip()}")

    def test_pipeline_conditions_allow_only_exclusive_duplicates(self):
        """绘制设置里同一个键只能出现在互斥分支；同一分支或条件之外重复都要报错。"""
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)/"pipeline.properties"
            source.write_text("#ifdef A\nsun=true\n#else\nsun=false\n#endif\n",encoding="utf-8")
            self.assertEqual(options.read_pipeline(source)["sun"],"false")  # 互斥分支允许，读取结果只用于检查。
            for text in ("sun=true\nsun=false\n","#ifdef A\nsun=true\nsun=false\n#endif\n","sun=true\n#ifdef A\nsun=false\n#endif\n","#ifdef A\nsun=true\n"):
                with self.subTest(text=text):
                    source.write_text(text,encoding="utf-8")
                    with self.assertRaises(ValueError):  # 可能同时生效的重复和缺少结尾都拒绝。
                        options.read_pipeline(source)

    def test_rain_darkening_applies_in_composite(self):
        """雨天变暗在合成阶段整体压暗，默认取零不改变画面。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_RAIN_DARKEN",found); self.assertEqual(found["OMNI_RAIN_DARKEN"].default,"0.0")  # 默认不压暗。
        text = (build.SHADERS/"effects/weather.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniWeather",text)  # 天气压暗独立成函数。
        self.assertIn("rainStrength * OMNI_RAIN_DARKEN",text)  # 压暗由降雨强度驱动。
        source = build.expand(build.SHADERS/"world0/composite.fsh")  # 从合成入口展开。
        self.assertIn("omniWeather(color)",source)  # 合成阶段包含雨天压暗。

    def test_planet_curvature_bends_distant_vertex(self):
        """行星曲率按水平距离压低远景顶点，默认取零不改变画面。"""
        found,_,_ = build.configuration()
        self.assertIn("OMNI_PLANET_CURVATURE",found); self.assertEqual(found["OMNI_PLANET_CURVATURE"].default,"0.0")  # 默认平地。
        text = (build.SHADERS/"effects/world.glsl").read_text(encoding="utf-8")
        self.assertIn("vec3 omniPlanetCurve",text)  # 曲率独立成函数。
        self.assertIn("OMNI_PLANET_CURVATURE",text)  # 强度参与下沉。
        self.assertIn("vec3 world = omniWorld(viewPosition);",text)  # 在世界空间里下沉，相机俯仰不改变弯曲方向。
        self.assertIn("(gbufferModelView * vec4(world, 1.0)).xyz",text)  # 算完换回相机空间。
        source = build.expand(build.SHADERS/"world0/dh_terrain.vsh")  # 从远景顶点入口展开。
        self.assertIn("omniPlanetCurve",source)  # 远景顶点包含曲率。

    def test_menu_pages_cover_every_category(self):
        """生成的菜单必须覆盖全部主分类，且每个分类至少有一个选项。"""
        found,_ = options.scan(build.SHADERS)  # 读取真实扫描结果。
        known = {name for name,_ in options.MAIN_PAGES}  # 主分类只在一处定义。
        used = {options.page_of(option) for option in found.values()}  # 每个选项实际落在的页面。
        self.assertEqual(used <= known,True,used-known)  # 不允许选项落到未登记的页面。
        self.assertEqual(known <= used,True,known-used)  # 不允许出现空分类。

    def test_every_option_has_tooltip(self):
        """每个选项都要有悬停说明，玩家才能不靠猜来调。"""
        found,_,_ = build.configuration()
        missing = [name for name,option in found.items() if not option.description]  # 缺说明的选项直接列出来。
        self.assertEqual(missing,[],missing)

    def test_menu_subpages_and_value_labels(self):
        """一个分类有多个效果时折叠成子页面，档位按钮显示玩家能看懂的取值名称。"""
        _,_,files = build.configuration()
        menu = files[build.SHADERS/"shaders.properties"]  # 读取真实生成内容。
        self.assertIn("screen.SKY = [SKY_ATMOSPHERE]",menu)  # 天空分类下有子页面入口。
        self.assertIn("screen.SKY_ATMOSPHERE = ",menu)  # 子页面自带选项列表。
        lang = files[build.SHADERS/"lang"/"zh_cn.lang"]
        self.assertIn("value.OMNI_RENDER_SCALE.50=",lang)  # 渲染缩放的档位名称已生成。
        self.assertIn("value.OMNI_DEBUG_VIEW.0=",lang)  # 调试视图的档位名称已生成。

