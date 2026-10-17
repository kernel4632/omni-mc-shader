# 算法参考与可复用实现

本文件是「算法外包」的总清单：每个效果去哪个宽松许可的项目里找现成实现。
原则：能直接用库的就用；许可不允许但原理公开的，读原理自己重写并改进；库很小（几百行）的，直接按 HOP 重写进项目，不引入依赖。

`libraries.md` 记录最终采用并打包的库；本文件范围更大，包含只作参考的实现。

## 四个主力来源（覆盖大多数效果）

| 项目 | 语言 | 许可 | 覆盖 |
| --- | --- | --- | --- |
| Google Filament | GLSL/C++ | Apache-2.0 | PBR、IBL、SSAO、SSR、TAA、DOF、泛光、体积雾、色调映射、色彩分级 |
| Godot Engine | GLSL 风格 | MIT | SSAO、SSR、SDFGI 全局光、体积雾、辉光、景深散景、运动模糊、TAA/FSR、天空、雾 |
| three.js | GLSL | MIT | BSDF、色调映射、雾、灯光；后处理含 SMAAPass、UnrealBloomPass、BokehPass、SSRPass、GTAOPass、TAARenderPass、FXAA |
| AMD FidelityFX | HLSL/GLSL | MIT（已核实 CACAO 等） | FSR 超分、CACAO 环境光遮蔽、SSSR 随机屏幕反射、SPD、LPM 色调映射、CAS、降噪器 |

## 按效果查表

| 效果 / 主题 | 参考实现 | 语言 | 许可 | 处理方式 |
| --- | --- | --- | --- | --- |
| 噪声（单纯形/值/沃利） | Ashima、Stefan Gustavson、FastNoiseLite、stb_perlin | GLSL/C | MIT / 公有领域 | 已用 Ashima；其余只补缺的噪声类型 |
| 蓝噪声采样 | Christoph Peters blue noise | 多语言 | MIT | 按原理重写 |
| 抗锯齿（形态学） | SMAA（iryoku/smaa） | HLSL/GLSL | MIT | 直接采用，自带查找表纹理 |
| 抗锯齿（时间） | Filament TAA、Godot TAA、three.js TAARenderPass、Karis 重投影 | GLSL | Apache-2.0 / MIT | 按原理重写 |
| 快速近似抗锯齿 | NVIDIA FXAA、three.js FXAAShader | GLSL | 宽松 | 按原理重写 |
| 超分 | FidelityFX FSR（EASU/RCAS）、SGSR | HLSL/GLSL | MIT（核对） | 直接采用或按原理重写 |
| 环境光遮蔽 | Intel XeGTAO、FidelityFX CACAO、three.js GTAOPass、Filament SSAO | GLSL/HLSL | MIT / Apache-2.0 | 直接采用 XeGTAO |
| 大气 / 天空 | Bruneton 预计算、wwwtyro glsl-atmosphere、Hosek-Wilkie、Preetham、Nishita | 多语言 | BSD-3 / 公有领域 / 公开论文 | 已用解析近似；后续换 Bruneton 或 Hosek-Wilkie |
| 云（体积） | Sebastian Lague Clouds、shadertoy 体积云、Horizon Zero Dawn 方案、Frostbite | C#/GLSL/论文 | MIT（SebLague 已核实）/ 公开论文 | 按原理重写 |
| 云（平面） | 各 shadertoy | GLSL | 公开 | 按原理重写 |
| 雾（体积） | Filament froxel fog、Godot volumetric fog、Frostbite volumetrics | GLSL/论文 | Apache-2.0 / MIT / 公开 | 按原理重写 |
| 阳光光柱 | GPU Gems 3 第 13 章、shadertoy god rays | GLSL/论文 | 公开 | 按原理重写 |
| 屏幕空间反射 | FidelityFX SSSR、Filament SSR、three.js SSRPass、Hi-Z SSR | HLSL/GLSL | MIT / Apache-2.0 | 按原理重写 |
| 反射降噪 | SVGF、FidelityFX Denoiser、时空降噪 | 论文/HLSL | 公开 / MIT | 按原理重写 |
| PBR / BRDF | Filament PBR、three.js BSDF、Khronos glTF 样例 | GLSL | Apache-2.0 / MIT | 直接参考或按原理重写 |
| 镜面抗锯齿 / 法线分布 | Filament、UE4 Karis 讲义、GGX 原论文 | GLSL/论文 | 公开 | 已自写，继续按论文改进 |
| 次表面散射 | GPU Gems 3 第 14 章、Filament SSS、散射近似 | 论文/GLSL | 公开 / Apache-2.0 | 按原理重写 |
| 彩色 / 透射阴影 | Unity 彩色半透明阴影、GPU Gems 透光阴影 | 论文 | 公开 | 按原理重写 |
| 接触硬化半影 | PCSS 原论文、Filament contact shadows | 论文/GLSL | 公开 / Apache-2.0 | 按原理重写 |
| 焦散 | GPU Gems 第 2 章（Wyman）、shadertoy 水焦散 | 论文/GLSL | 公开 | 按原理重写 |
| 全局光（体素） | Godot SDFGI、NVIDIA VXGI 讲义 | GLSL/论文 | MIT / 公开 | 按原理重写 |
| 全局光（探针） | NVIDIA DDGI | 论文 | 公开 | 按原理重写 |
| 全局光（光传播体积） | CryEngine LPV | 论文 | 公开 | 按原理重写 |
| 全局光（反射阴影图） | Crytek RSM | 论文 | 公开 | 按原理重写 |
| 水（波） | GPU Gems 水面、Catlike Coding 水体、Gerstner/Tessendorf | GLSL/论文 | 公开 / MIT | 已自写，按论文改进 |
| 水（FFT 海面） | Tessendorf、GPU FFT ocean 实现 | 论文/GLSL | 公开 | 按原理重写 |
| 水（吸收/散射/折射） | 真实水介质常数、各 shadertoy | 论文/GLSL | 公开 | 已自写 |
| 泛光 | Unity 物理泛光、COD 泛光、Filament bloom、three.js UnrealBloomPass | GLSL | Apache-2.0 / MIT | 按原理重写 |
| 景深 / 散景 | Filament DOF、Kotelnikov DOF、three.js BokehPass、六边形散景 | GLSL/论文 | Apache-2.0 / MIT / 公开 | 按原理重写 |
| 运动模糊 | Filament / Godot 运动模糊、GPU Gems 3 第 27 章 | GLSL/论文 | Apache-2.0 / MIT / 公开 | 按原理重写 |
| 色调映射 | ACES（AMPAS）、AgX（Sobotka）、Uchimura、Hable Filmic、FidelityFX LPM | 多语言 | 公开 / MIT | 已自写 AgX/ACES，其余按需 |
| 色彩空间 / 分级 | colour-science（Python）、Filament color grading、three.js ColorManagement | 多语言 | BSD-3 / Apache-2.0 / MIT | 按原理重写 |
| 极光 | shadertoy aurora | GLSL | 公开 | 按原理重写 |
| 星空 | shadertoy starfield、three.js | GLSL | 公开 / MIT | 已自写 |
| 季节 / 生物群系颜色 | 参考包 settings 的公开做法 | 论文/配置 | 需自行设计 | 自己设计 |
| 行星曲率 | 各 shadertoy 曲面地球 | GLSL | 公开 | 按原理重写 |

## 语言的可用性

- **可参考并移植**：GLSL、HLSL、Cg、Godot 着色语言、Unity/Unreal 的公开文章（只读原理，不复制引擎源码）、Python（颜色科学）。
- **只读原理，不复制代码**：Unreal Engine、Unity 引擎源码（许可证限制）。
- **不要碰**：主流光影包源码（版权保留）、许可不明或禁止再分发的项目。

## 采用与重写的判断标准

1. **直接采用**：许可宽松（MIT/BSD/Apache/公有领域）、能用 `#include` 接入、GLSL 版本兼容、体积可接受。
2. **按原理重写**：许可受限，或语言不同，或实现很依赖特定引擎。写进 `common/` 或对应 `effects/` 文件，按 HOP 讲清做什么、为什么。
3. **小库直接重写**：整段算法几百行以内（噪声、色调映射、泛光、散景、白平衡等），直接按原理写进项目，不引入依赖，顺便按我们的需要改进。
4. **登记**：采用或重写自公开论文时，在文件头注明来源与论文名；采用第三方文件时登记 `dependencies.json` 与 `THIRD_PARTY.md`。

## 下一步

1. 逐个核对标「需核实」的许可（FidelityFX、Sebastian Lague、若干 shadertoy）。
2. 先落地四个主力来源里最适合直接用的：SMAA、XeGTAO、glsl-atmosphere、Bruneton。
3. 其余按 `docs/eclipse-parity.md` 的合并建议与 `docs/parity.md` 的偏离记录，读论文重写。
