// 共用纯计算：颜色空间转换、感知亮度、安全归一化和可重复空间噪声，不包含任何业务效果。
// 调用位置：需要这些计算的效果文件，用自己的文件头一行 include 引入本文件。
// 可复制示例：
//   需要全部数学函数的文件直接引用本文件。
//   omniLinear(texture)                         // 贴图颜色转到线性空间
//   omniLuminance(color)                        // 按人眼敏感度取亮度
//   omniNoise(worldPosition)                    // 可重复的空间噪声
// 设计取舍：这些是多个效果共用的纯函数，集中放这里，效果文件不各自复制一份；
// 内部互相信任，调用方保证传入的是普通 vec3，本文件不重复校验也不吞错；
// 名字统一带 `omni` 前缀，避免和加载器内置函数重名。
#ifndef OMNI_MATH
#define OMNI_MATH

// --- 颜色空间与亮度：贴图存的是显示颜色，光照要在线性空间计算 ---

// 感知亮度：把线性空间颜色压成一个数，供明暗判断使用。
// 为什么三个权重不同：人眼对绿色最敏感、对蓝色最迟钝，等权相加会把蓝天和绿地算成一样亮。
float omniLuminance(vec3 color) { return dot(color, vec3(0.2126, 0.7152, 0.0722)); }

// 显示颜色转线性：贴图和配置里的颜色按显示曲线存放，直接拿去做光照会偏暗，先按标准曲线还原。
// 为什么分两段：小数值段走直线、大数值段走幂函数，这是显示编码的定义，均匀一条曲线会把暗部算错。
vec3 omniLinear(vec3 color) { return mix(color / 12.92, pow((color + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), color)); }

// 线性转回显示颜色：光照都在线性空间计算，最终写屏前要编回去，否则画面整体偏暗。
vec3 omniSrgb(vec3 color) { return mix(color * 12.92, 1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), color)); }

// --- 向量：安全归一化 ---

// 安全归一化：原本是除以长度得到单位向量，但长度为零时普通除法会得到无穷，再扩散出去污染整幅画面。
// 为什么把长度下限抬到 1e-10：极短的向量也会被放大成巨大方向，先兜住一个极小值，让退化输入收敛到零方向。
vec3 omniNormalize(vec3 vector) { return vector * inversesqrt(max(dot(vector, vector), 1e-10)); }

// --- 空间噪声：给云雾、雪边这类效果提供连续且可复现的随机场 ---

// 二维哈希：把坐标打散成 0 到 1 之间的一个数，同样的输入永远得到同样的输出。
// 为什么用正弦再乘大数：三角函数先把坐标搅乱，再乘一个没有规律的大数取小数，是便宜好用的伪随机办法。
float omniHash(vec2 point) { return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453); }

// 取一层噪声：四个角点的随机值先横向混合、再纵向混合，得到这一层的平滑值。
// 上下两层共用这一步，区别只是传入的种子不同。
float omniNoiseLayer(vec2 seed, vec2 local) {
    float bottom = mix(omniHash(seed), omniHash(seed + vec2(1, 0)), local.x); // 下边两角横向混合。
    float top = mix(omniHash(seed + vec2(0, 1)), omniHash(seed + vec2(1, 1)), local.x); // 上边两角横向混合。
    return mix(bottom, top, local.y); // 上下两条边再纵向混合成该层的值。
}

// 三维值噪声：在整数格点取随机值，格内平滑插值，得到连续且可复现的随机场。
// 为什么先平滑再插值：直接插值会在格点留下硬折边，用平滑曲线过渡才看不出格子。
float omniNoise(vec3 point) {
    vec3 cell = floor(point); // 点所在整数格，用来定位八个角点。
    vec3 local = fract(point); // 点在格内的相对位置，用来在角点之间插值。
    local = local * local * (3.0 - 2.0 * local); // 平滑曲线，让格点处的过渡没有硬折边。
    vec2 seed = cell.xy + cell.z * vec2(37.0, 17.0); // 三维格映射成二维种子，让每层高度拿到的随机值不同。
    float lower = omniNoiseLayer(seed, local.xy); // 下层四个角点的混合值。
    float upper = omniNoiseLayer(seed + vec2(37.0, 17.0), local.xy); // 换种子偏移取上层，避免上下重复同一组随机值。
    return mix(lower, upper, local.z); // 按高度把上下两层连续混合成一个值。
}

#endif
