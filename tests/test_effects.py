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
