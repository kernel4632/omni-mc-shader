/*
探针共用的无符号纹理别名：Slang 只有 `Texture*` 泛型，没有 GLSL 的 `usampler*` 名字。
调用位置：需要方块光表或体素编号图的模块探针，在引入模块前包含本文件。
设计原因与取舍：
    别名只补类型名字，不改模块里的算式、常数与取格写法；生成器仍把
    `Usampler1D` / `Usampler3D` 降级成 GLSL 的 `usampler1D` / `usampler3D`。
*/
typealias Usampler1D = Texture1D<uint4>; // 一维无符号纹理，方块光表按四通道打包。
typealias Usampler3D = Texture3D<uint4>; // 三维无符号纹理，体素编号与光照遮罩共用。
