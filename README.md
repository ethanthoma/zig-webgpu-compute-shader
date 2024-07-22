<h3 align="center">
    Zig WebGPU Compute Shader Example
</h3>

This codebase uses WebGPU to run a really simple shader in zig. I use nix as the
build tool to fetch wgpu-native and compile the rust code. It should be pretty
easy to do without nix.

The compute shader is taken from [here](https://github.com/eliemichel/LearnWebGPU-Code/blob/step201/resources/compute-shader.wgsl).

The flake.nix uses [zig2nix](https://github.com/Cloudef/zig2nix) for building 
and running the code. I set it to use Vulkan but it is pretty easy to use any 
other backend.

## Running

To run the code, simply run:
```
nix run github:ethanthoma/zig-webgpu-compute-shader
```
Or clone the repo locally and run `nix run`.

### Input and Output

The input to the compute shader is an array of 32 bit floats. The array is 64 
elements long. The value of the elements start at 1 and count to 64. The code
below is how it is initalized:
```zig
var input_data: [64]f32 = undefined;
for (input_data, 0..) |_, i| {
    input_data[i] = @floatFromInt(i + 1);
}
```

The output from the shader is each element multipled by 2 and then added to it 
by 1. The output is below:
```
[0] = 3e0, [1] = 5e0, [2] = 7e0, [3] = 9e0, [4] = 1.1e1, [5] = 1.3e1,
[6] = 1.5e1, [7] = 1.7e1, [8] = 1.9e1, [9] = 2.1e1, [10] = 2.3e1, [11] = 2.5e1,
[12] = 2.7e1, [13] = 2.9e1, [14] = 3.1e1, [15] = 3.3e1, [16] = 3.5e1, 
[17] = 3.7e1, [18] = 3.9e1, [19] = 4.1e1, [20] = 4.3e1, [21] = 4.5e1,
[22] = 4.7e1, [23] = 4.9e1, [24] = 5.1e1, [25] = 5.3e1, [26] = 5.5e1,
[27] = 5.7e1, [28] = 5.9e1, [29] = 6.1e1, [30] = 6.3e1, [31] = 6.5e1,
[32] = 6.7e1, [33] = 6.9e1, [34] = 7.1e1, [35] = 7.3e1, [36] = 7.5e1,
[37] = 7.7e1, [38] = 7.9e1, [39] = 8.1e1, [40] = 8.3e1, [41] = 8.5e1,
[42] = 8.7e1, [43] = 8.9e1, [44] = 9.1e1, [45] = 9.3e1, [46] = 9.5e1,
[47] = 9.7e1, [48] = 9.9e1, [49] = 1.01e2, [50] = 1.03e2, [51] = 1.05e2,
[52] = 1.07e2, [53] = 1.09e2, [54] = 1.11e2, [55] = 1.13e2, [56] = 1.15e2,
[57] = 1.17e2, [58] = 1.19e2, [59] = 1.21e2, [60] = 1.23e2, [61] = 1.25e2,
[62] = 1.27e2, [63] = 1.29e2,
```
