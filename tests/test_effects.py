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
