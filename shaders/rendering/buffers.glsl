/*
中间画面唯一约定：每个编号画面的格式、通道含义、写入者和读取者只在这里定义一次。
调用位置：由 composite.glsl、lighting.glsl、terrain.glsl、temporal.glsl、final.glsl 等绘制流程引入。
可复制示例：
    `texture(colortex1, uv)`                 按屏幕坐标采样法线画面
    `texelFetch(colortex7, pixel, 0).a`      精确读取像素的几何有效标记
    `texture(colortex5, vec2(0.5)).g`        读取时间合成算出的曝光
为什么集中在这里：画面编号是跨文件接口，写入者和读取者各存一份就会改一处忘一处，
接手者无法判断哪份才准。这里一次写清，其他文件只按编号引用。
取舍：编号按绘制先后排列，方便从上往下读；历史画面要跨帧保留，所以单独关闭每帧清除。
*/

// 格式指令行只写指令、行尾不带说明：加载器按名字读取格式，格式名会由加载器在编译时补上，自己定义反而会把名字换成数字。
// 缓冲格式：加载器按名字读取格式，而 GLSL 不认识这些名字，所以格式指令放进块注释，每行只写指令本身。
// 名称含义：RGBA16F 保留高光与法线等连续数据，RGBA32F 保留米制深度；改格式只改这里的名字。
/*
零号画面：场景线性颜色。几何与前向照明写颜色，时间合成回写稳定结果，最终显示读取；允许高于屏幕白色的线性照明。
const int colortex0Format = RGBA16F;
一号画面：视空间法线与物体类别。几何写，屏幕后处理与时间阶段读；透明阶段不改此画面；保留法线和类别的精度。
const int colortex1Format = RGBA16F;
二号画面：材质参数与原版天空光。几何写，反射与氛围读；粗糙度要连续变化，八位定长会出现台阶。
const int colortex2Format = RGBA16F;
三号画面：不透明颜色快照。延迟阶段写，透明折射、屏幕反射与间接光读；透明绘制会改动零号画面，这里留一份改动前的副本。
const int colortex3Format = RGBA16F;
四号画面：上一帧线性颜色。时间合成写，时间合成下一帧与抗锯齿读；历史跨帧保留，所以不每帧清除。
const int colortex4Format = RGBA16F;
五号画面：时间元数据。时间合成写，重投影、自动曝光与最终镜头读；帧号、绝对相机位置和米制深度需要较高精度。
const int colortex5Format = RGBA32F;
六号画面：抗锯齿之前的合成颜色。合成阶段写，时间合成与自动曝光读；「渲染缩放」会把它缩到一半或四分之三。
const int colortex6Format = RGBA16F;
七号画面：原版光照数据。几何写，屏幕后处理、时间阶段与调试读；光照等级要连续插值，有效标记是精确开关。
const int colortex7Format = RGBA16F;
八号画面：水表面法线与真实视空间深度。水面几何写，合成与时间阶段读；米制深度要覆盖远景，半精度会在远处丢失分辨。
const int colortex8Format = RGBA32F;
*/
// 六号画面被缩放后，写入方必须用 `omniPixel(uv)` 取全分辨率像素，不能用 `gl_FragCoord`；
// 读取方只能用 `texture(colortex6, uv)` 按比例坐标采样，不能用 `texelFetch`。

// 四号与五号是历史画面，要带着上一帧的内容进入下一帧，所以关闭每帧清除。
const bool colortex4Clear = false; // 历史跨帧保留。
const bool colortex5Clear = false; // 历史状态跨帧保留。

// 零号清成黑色：原版天空几何已关闭，天空像素在延迟阶段之前只剩日月等贴图的颜色，
// 开启「使用资源包天空」时延迟阶段把这部分叠加到自定义天空上；清成雾色会把雾色也一起叠进去。
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0); // 天空像素只保留贴图贡献。
// 一号清成朝前的浮点法线，天空这类没有几何的像素也有一个无害的默认方向。
const vec4 colortex1ClearColor = vec4(0.5, 0.5, 1.0, 0.0); // 天空法线采用朝前的无害默认值。
// 二号清成粗糙非金属，没有材质信息的像素不会反光。
const vec4 colortex2ClearColor = vec4(1.0, 0.0, 0.0, 1.0); // 无材质使用粗糙非金属。
// 七号清成无效，没有几何或覆盖层的像素不参与屏幕后处理。
const vec4 colortex7ClearColor = vec4(0.0, 0.0, 0.0, 0.0); // 没有几何或覆盖层时标记无有效元数据。
// 八号清成零，表示没有水面；每帧清除防止上一帧的水面残留下来。
const vec4 colortex8ClearColor = vec4(0.0, 0.0, 0.0, 0.0); // 没有水表面的默认值，禁止跨帧残留。
