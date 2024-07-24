const std = @import("std");
const assert = std.debug.assert;

const wgpu = @cImport({
    @cInclude("wgpu.h");
});

const Error = error{
    FailedToCreateInstance,
    FailedToGetAdapter,
    FailedToGetDevice,
    FailedToGetQueue,
    FailedToCreateShaderModule,
    FailedToCreateBuffer,
    FailedToCreateBindGroupLayout,
    FailedToCreateBindGroup,
    FailedToCreatePipelineLayout,
    FailedToCreateComputePipeline,
    FailedToCreateCommandEncoder,
    FailedToCreateComputePassEncoder,
    FailedToCreateCommandBuffer,
};

pub fn main() !void {
    // Create instance
    const instance: wgpu.WGPUInstance = retval: {
        if (wgpu.wgpuCreateInstance(&.{})) |instance| {
            break :retval instance;
        } else {
            std.debug.print("Failed to create wgpu instance\n", .{});
            return Error.FailedToCreateInstance;
        }
    };
    defer wgpu.wgpuInstanceRelease(instance);

    // Get adpater
    const adapter: wgpu.WGPUAdapter = retval: {
        const options = wgpu.WGPURequestAdapterOptions{};

        if (requestAdapterSync(instance, &options)) |adapter| {
            break :retval adapter;
        } else {
            std.debug.print("Failed to get adapter\n", .{});
            return Error.FailedToGetAdapter;
        }
    };
    defer wgpu.wgpuAdapterRelease(adapter);

    // Get device
    const device: wgpu.WGPUDevice = retval: {
        const descriptor = wgpu.WGPUDeviceDescriptor{};

        if (requestDeviceSync(adapter, &descriptor)) |device| {
            break :retval device;
        } else {
            std.debug.print("Failed to get adapter\n", .{});
            return Error.FailedToGetDevice;
        }
    };
    defer wgpu.wgpuDeviceRelease(device);

    // Get queue
    const queue: wgpu.WGPUQueue = retval: {
        if (wgpu.wgpuDeviceGetQueue(device)) |queue| {
            break :retval queue;
        } else {
            std.debug.print("Failed to get queue\n", .{});
            return Error.FailedToGetQueue;
        }
    };
    defer wgpu.wgpuQueueRelease(queue);

    // Create shader module
    const shader: wgpu.WGPUShaderModule = retval: {
        const source: [*c]const u8 = @ptrCast(@embedFile("compute-shader"));

        const descriptor = wgpu.WGPUShaderModuleDescriptor{
            .label = "compute-shader",
            .nextInChain = @as(*wgpu.WGPUChainedStruct, @ptrCast(@constCast(&wgpu.WGPUShaderModuleWGSLDescriptor{
                .code = source,
                .chain = wgpu.WGPUChainedStruct{
                    .sType = wgpu.WGPUSType_ShaderModuleWGSLDescriptor,
                },
            }))),
        };

        if (wgpu.wgpuDeviceCreateShaderModule(device, &descriptor)) |shader| {
            break :retval shader;
        } else {
            std.debug.print("Failed to create shader module\n", .{});
            return Error.FailedToCreateShaderModule;
        }
    };
    defer wgpu.wgpuShaderModuleRelease(shader);

    // Create input and output buffers
    var input_data: [64]f32 = undefined;
    for (input_data, 0..) |_, i| {
        input_data[i] = @floatFromInt(i + 1);
    }

    const buffer_size = @sizeOf([64]f32);

    const input_buffer: wgpu.WGPUBuffer = retval: {
        const input_buffer_descriptor = wgpu.WGPUBufferDescriptor{
            .usage = wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopyDst,
            .size = buffer_size,
            .mappedAtCreation = 0,
        };

        if (wgpu.wgpuDeviceCreateBuffer(device, &input_buffer_descriptor)) |input_buffer| {
            break :retval input_buffer;
        } else {
            std.debug.print("Failed to create input buffer\n", .{});
            return Error.FailedToCreateBuffer;
        }
    };
    defer wgpu.wgpuBufferRelease(input_buffer);

    const output_buffer: wgpu.WGPUBuffer = retval: {
        const output_buffer_descriptor = wgpu.WGPUBufferDescriptor{
            .usage = wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopySrc,
            .size = buffer_size,
            .mappedAtCreation = 0,
        };

        if (wgpu.wgpuDeviceCreateBuffer(device, &output_buffer_descriptor)) |output_buffer| {
            break :retval output_buffer;
        } else {
            std.debug.print("Failed to create output buffer\n", .{});
            return Error.FailedToCreateBuffer;
        }
    };
    defer wgpu.wgpuBufferRelease(output_buffer);

    const map_buffer: wgpu.WGPUBuffer = retval: {
        const map_buffer_descriptor = wgpu.WGPUBufferDescriptor{
            .usage = wgpu.WGPUBufferUsage_CopyDst | wgpu.WGPUBufferUsage_MapRead,
            .size = buffer_size,
            .mappedAtCreation = 0,
        };

        if (wgpu.wgpuDeviceCreateBuffer(device, &map_buffer_descriptor)) |map_buffer| {
            break :retval map_buffer;
        } else {
            std.debug.print("Failed to create map buffer\n", .{});
            return Error.FailedToCreateBuffer;
        }
    };
    defer wgpu.wgpuBufferRelease(map_buffer);

    // Create bind group layout
    const bind_group_layout = retval: {
        const bind_group_layout_descriptor = wgpu.WGPUBindGroupLayoutDescriptor{
            .entryCount = 2,
            .entries = &[_]wgpu.WGPUBindGroupLayoutEntry{
                wgpu.WGPUBindGroupLayoutEntry{ .binding = 0, .visibility = wgpu.WGPUShaderStage_Compute, .buffer = wgpu.WGPUBufferBindingLayout{ .type = wgpu.WGPUBufferBindingType_ReadOnlyStorage } },
                wgpu.WGPUBindGroupLayoutEntry{ .binding = 1, .visibility = wgpu.WGPUShaderStage_Compute, .buffer = wgpu.WGPUBufferBindingLayout{ .type = wgpu.WGPUBufferBindingType_Storage } },
            },
        };

        if (wgpu.wgpuDeviceCreateBindGroupLayout(device, &bind_group_layout_descriptor)) |bind_group_layout| {
            break :retval bind_group_layout;
        } else {
            std.debug.print("Failed to create bind group layout\n", .{});
            return Error.FailedToCreateBindGroupLayout;
        }
    };
    defer wgpu.wgpuBindGroupLayoutRelease(bind_group_layout);

    // Create bind group
    const bind_group: wgpu.WGPUBindGroup = retval: {
        const bind_group_descriptor = wgpu.WGPUBindGroupDescriptor{
            .layout = bind_group_layout,
            .entryCount = 2,
            .entries = &[_]wgpu.WGPUBindGroupEntry{
                wgpu.WGPUBindGroupEntry{ .binding = 0, .buffer = input_buffer, .offset = 0, .size = buffer_size },
                wgpu.WGPUBindGroupEntry{ .binding = 1, .buffer = output_buffer, .offset = 0, .size = buffer_size },
            },
        };

        if (wgpu.wgpuDeviceCreateBindGroup(device, &bind_group_descriptor)) |bind_group| {
            break :retval bind_group;
        } else {
            std.debug.print("Failed to create bind group\n", .{});
            return Error.FailedToCreateBindGroup;
        }
    };
    defer wgpu.wgpuBindGroupRelease(bind_group);

    // Create pipeline layout
    const pipeline_layout: wgpu.WGPUPipelineLayout = retval: {
        const pipeline_layout_descriptor = wgpu.WGPUPipelineLayoutDescriptor{
            .bindGroupLayoutCount = 1,
            .bindGroupLayouts = &bind_group_layout,
        };

        if (wgpu.wgpuDeviceCreatePipelineLayout(device, &pipeline_layout_descriptor)) |pipeline_layout| {
            break :retval pipeline_layout;
        } else {
            std.debug.print("Failed to create pipeline layout\n", .{});
            return Error.FailedToCreatePipelineLayout;
        }
    };
    defer wgpu.wgpuPipelineLayoutRelease(pipeline_layout);

    // Create compute pipeline
    const compute_pipeline: wgpu.WGPUComputePipeline = retval: {
        const compute_pipeline_descriptor = wgpu.WGPUComputePipelineDescriptor{
            .layout = pipeline_layout,
            .compute = wgpu.WGPUProgrammableStageDescriptor{
                .constantCount = 0,
                .constants = null,
                .entryPoint = "computeStuff",
                .module = shader,
            },
        };

        if (wgpu.wgpuDeviceCreateComputePipeline(device, &compute_pipeline_descriptor)) |compute_pipeline| {
            break :retval compute_pipeline;
        } else {
            std.debug.print("Failed to create compute pipeline\n", .{});
            return Error.FailedToCreateComputePipeline;
        }
    };
    defer wgpu.wgpuComputePipelineRelease(compute_pipeline);

    // Initialize a command encoder
    const command_encoder: wgpu.WGPUCommandEncoder = retval: {
        const command_encoder_descriptor = wgpu.WGPUCommandEncoderDescriptor{};

        if (wgpu.wgpuDeviceCreateCommandEncoder(device, &command_encoder_descriptor)) |command_encoder| {
            break :retval command_encoder;
        } else {
            std.debug.print("Failed to create command encoder\n", .{});
            return Error.FailedToCreateCommandEncoder;
        }
    };
    defer wgpu.wgpuCommandEncoderRelease(command_encoder);

    // Create compute pass
    const compute_pass_encoder: wgpu.WGPUComputePassEncoder = retval: {
        const compute_pass_descriptor = wgpu.WGPUComputePassDescriptor{};

        if (wgpu.wgpuCommandEncoderBeginComputePass(command_encoder, &compute_pass_descriptor)) |compute_pass_encoder| {
            break :retval compute_pass_encoder;
        } else {
            std.debug.print("Failed to create compute pass encoder\n", .{});
            return Error.FailedToCreateComputePassEncoder;
        }
    };
    defer wgpu.wgpuComputePassEncoderRelease(compute_pass_encoder);

    // Use compute pass
    wgpu.wgpuComputePassEncoderSetPipeline(compute_pass_encoder, compute_pipeline);
    wgpu.wgpuComputePassEncoderSetBindGroup(compute_pass_encoder, 0, bind_group, 0, null);

    const invocationCount: u32 = buffer_size / @sizeOf(f32);
    const workgroupSize: u32 = 32;
    const workgroupCount: u32 = (invocationCount + workgroupSize - 1) / workgroupSize;
    wgpu.wgpuComputePassEncoderDispatchWorkgroups(compute_pass_encoder, workgroupCount, 1, 1);

    // Finalize compute pass
    wgpu.wgpuComputePassEncoderEnd(compute_pass_encoder);

    // Before encoder finish
    wgpu.wgpuCommandEncoderCopyBufferToBuffer(command_encoder, output_buffer, 0, map_buffer, 0, buffer_size);

    // Encode commands
    const command_buffer: wgpu.WGPUCommandBuffer = retval: {
        if (wgpu.wgpuCommandEncoderFinish(command_encoder, null)) |command_buffer| {
            break :retval command_buffer;
        } else {
            std.debug.print("Failed to create command buffer\n", .{});
            return Error.FailedToCreateCommandBuffer;
        }
    };
    defer wgpu.wgpuCommandBufferRelease(command_buffer);

    // Submit commands
    wgpu.wgpuQueueWriteBuffer(queue, input_buffer, 0, &input_data, buffer_size);
    wgpu.wgpuQueueSubmit(queue, 1, &command_buffer);

    // Wait for GPU work to complete
    const onQueueWorkDone = struct {
        fn func(status: wgpu.WGPUQueueWorkDoneStatus, pUserData: ?*anyopaque) callconv(.C) void {
            _ = pUserData;
            std.debug.print("Queued work finished with status: {}", .{status});
        }
    }.func;
    wgpu.wgpuQueueOnSubmittedWorkDone(queue, onQueueWorkDone, null);

    std.time.sleep(1_000_000_000);

    wgpu.wgpuBufferMapAsync(map_buffer, wgpu.WGPUMapMode_Read, 0, buffer_size, onMap, null);
    defer wgpu.wgpuBufferUnmap(map_buffer);

    _ = wgpu.wgpuDevicePoll(device, 1, null);

    const buf: *[64]f32 = @ptrCast(@alignCast(wgpu.wgpuBufferGetMappedRange(map_buffer, 0, buffer_size)));

    std.debug.print("\n", .{});
    for (buf, 0..) |val, i| {
        std.debug.print("[{}] = {}, ", .{ i, val });
    }
    std.debug.print("\n", .{});
}

fn onMap(status: wgpu.WGPUBufferMapAsyncStatus, userdata: ?*anyopaque) callconv(.C) void {
    _ = userdata;

    std.debug.print("Map buffer status: {}\n", .{status});
}

fn requestAdapterSync(instance: wgpu.WGPUInstance, options: *const wgpu.WGPURequestAdapterOptions) ?wgpu.WGPUAdapter {
    const UserData = struct {
        adapter: ?wgpu.WGPUAdapter = null,
        requestEnded: bool = false,
    };

    var userData: UserData = .{};

    const onAdapterRequestEnded = struct {
        fn func(status: wgpu.WGPURequestAdapterStatus, adapter: wgpu.WGPUAdapter, message: [*c]const u8, pUserData: ?*anyopaque) callconv(.C) void {
            const _userData: *UserData = @ptrCast(@alignCast(pUserData));
            if (status == wgpu.WGPURequestAdapterStatus_Success) {
                _userData.adapter = adapter;
            } else {
                std.debug.print("Could not get WebGPU adapter: {s}\n", .{message});
            }
            _userData.requestEnded = true;
        }
    }.func;

    wgpu.wgpuInstanceRequestAdapter(
        instance,
        options,
        onAdapterRequestEnded,
        @as(?*anyopaque, @ptrCast(&userData)),
    );

    assert(userData.requestEnded);

    return userData.adapter;
}

fn requestDeviceSync(adapter: wgpu.WGPUAdapter, descriptor: *const wgpu.WGPUDeviceDescriptor) ?wgpu.WGPUDevice {
    const UserData = struct {
        device: ?wgpu.WGPUDevice = null,
        requestEnded: bool = false,
    };

    var userData: UserData = .{};

    const onDeviceRequestEnded = struct {
        fn func(status: wgpu.WGPURequestDeviceStatus, device: wgpu.WGPUDevice, message: [*c]const u8, pUserData: ?*anyopaque) callconv(.C) void {
            const _userData: *UserData = @ptrCast(@alignCast(pUserData));
            if (status == wgpu.WGPURequestDeviceStatus_Success) {
                _userData.device = device;
            } else {
                std.debug.print("Could not get WebGPU device: {s}\n", .{message});
            }
            _userData.requestEnded = true;
        }
    }.func;

    wgpu.wgpuAdapterRequestDevice(
        adapter,
        descriptor,
        onDeviceRequestEnded,
        @as(?*anyopaque, @ptrCast(&userData)),
    );

    assert(userData.requestEnded);

    return userData.device;
}
