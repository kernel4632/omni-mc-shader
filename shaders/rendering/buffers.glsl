// 中间画面唯一约定：由合成与最终流程引入，示例 texture(colortex1, uv)。
// 零：几何写入线性前向照明；时间合成回写最终线性颜色；最终显示读取。
// 一：不透明几何写入视空间法线编码与类别；零普通、二手、三远景；透明阶段不改此附件。
// 二：几何写入线性粗糙度、金属标志、自发光、天空光；反射与氛围读取。
// 三：延迟阶段保存不透明线性颜色；水折射、反射与间接光读取，透明阶段不写。
// 四：时间合成写入上一帧线性颜色与有效标记；下一帧时间合成读取。
// 五：时间合成写入米制深度、曝光、帧号、有效标记；下一帧重投影读取。
// 六：合成写入抗锯齿之前的线性颜色；时间合成读取。
// 七：方块光、天空光、水来源、几何有效标志；水来源零无、一近景、二远景；覆盖层有效标志为零。
// 八：透明水写入编码法线与负的实际视空间深度；玻璃清零；合成重建匹配的水表面，附件自身每帧清除。
// 零的透明度在时间阶段改为历史连续性与几何有效标记；最终镜头读取，不再检查已翻转的第五附件。
// 历史五的左下角保存尺寸、维度标志和帧号；第二像素保存相机位置和帧号。
// 历史四与五在分辨率或重载时由加载器重新分配；尺寸元数据再次拒绝旧历史。
const int colortex0Format = RGBA16F; // 允许高于屏幕白色的线性照明。
const int colortex1Format = RGBA16F; // 保留法线和类别的精度。
const int colortex2Format = RGBA16F; // 保留材质参数。
const int colortex3Format = RGBA16F; // 不透明辐射快照。
const int colortex4Format = RGBA16F; // 时间颜色历史。
const int colortex5Format = RGBA32F; // 帧号、绝对相机位置和米制深度需要较高精度。
const int colortex6Format = RGBA16F; // 合成颜色。
const int colortex7Format = RGBA16F; // 原版光照数据。
const int colortex8Format = RGBA32F; // 水法线与米制视深度，覆盖远景精度需求。
const bool colortex4Clear = false; // 历史跨帧保留。
const bool colortex5Clear = false; // 历史状态跨帧保留。
const vec4 colortex1ClearColor = vec4(0.5, 0.5, 1.0, 0.0); // 天空法线采用朝前的无害默认值。
const vec4 colortex2ClearColor = vec4(1.0, 0.0, 0.0, 1.0); // 无材质使用粗糙非金属。
const vec4 colortex7ClearColor = vec4(0.0, 0.0, 0.0, 0.0); // 没有几何或覆盖层时标记无有效元数据。
const vec4 colortex8ClearColor = vec4(0.0); // 没有水表面的默认值，禁止跨帧残留。
