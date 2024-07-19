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
nix run
```

The input to the shader is a 64 long float 32 array ranging from 1 to 64;
The shader simply multiplies the array by 2 and adds 1.
