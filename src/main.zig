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
    const instance: wgpu.WGPUInstance = wgpu.wgpuCreateInstance(
        &wgpu.WGPUInstanceDescriptor{},
    ) orelse {
        std.debug.print("Failed to create wgpu instance\n", .{});
        return Error.FailedToCreateInstance;
    };
    defer wgpu.wgpuInstanceRelease(instance);

    // Get adpater
    const adapter: wgpu.WGPUAdapter = requestAdapterSync(
        instance,
        &wgpu.WGPURequestAdapterOptions{},
    ) orelse {
        std.debug.print("Failed to get adapter\n", .{});
        return Error.FailedToGetAdapter;
    };
    defer wgpu.wgpuAdapterRelease(adapter);

    // Get device
    const device: wgpu.WGPUDevice = requestDeviceSync(
        adapter,
        &wgpu.WGPUDeviceDescriptor{},
    ) orelse {
        std.debug.print("Failed to get device\n", .{});
        return Error.FailedToGetDevice;
    };
    defer wgpu.wgpuDeviceRelease(device);

    // Get queue
    const queue: wgpu.WGPUQueue = wgpu.wgpuDeviceGetQueue(device) orelse {
        std.debug.print("Failed to get queue\n", .{});
        return Error.FailedToGetQueue;
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

    // Create input buffer
    var input_data: [64]f32 = undefined;
    for (input_data, 0..) |_, i| {
        input_data[i] = @floatFromInt(i + 1);
    }

    const buffer_size = @sizeOf([64]f32);

    const input_buffer: wgpu.WGPUBuffer = wgpu.wgpuDeviceCreateBuffer(
        device,
        &wgpu.WGPUBufferDescriptor{
            .usage = wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopyDst,
            .size = buffer_size,
            .mappedAtCreation = 0,
        },
    ) orelse {
        std.debug.print("Failed to create input buffer\n", .{});
        return Error.FailedToCreateBuffer;
    };
    defer wgpu.wgpuBufferRelease(input_buffer);

    // Create output buffer
    const output_buffer: wgpu.WGPUBuffer = wgpu.wgpuDeviceCreateBuffer(
        device,
        &wgpu.WGPUBufferDescriptor{
            .usage = wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopySrc,
            .size = buffer_size,
            .mappedAtCreation = 0,
        },
    ) orelse {
        std.debug.print("Failed to create output buffer\n", .{});
        return Error.FailedToCreateBuffer;
    };
    defer wgpu.wgpuBufferRelease(output_buffer);

    // Create map buffer
    const map_buffer: wgpu.WGPUBuffer = wgpu.wgpuDeviceCreateBuffer(
        device,
        &wgpu.WGPUBufferDescriptor{
            .usage = wgpu.WGPUBufferUsage_CopyDst | wgpu.WGPUBufferUsage_MapRead,
            .size = buffer_size,
            .mappedAtCreation = 0,
        },
    ) orelse {
        std.debug.print("Failed to create map buffer\n", .{});
        return Error.FailedToCreateBuffer;
    };
    defer wgpu.wgpuBufferRelease(map_buffer);

    // Create bind group layout
    const bind_group_layout = wgpu.wgpuDeviceCreateBindGroupLayout(
        device,
        &wgpu.WGPUBindGroupLayoutDescriptor{
            .entryCount = 2,
            .entries = &[_]wgpu.WGPUBindGroupLayoutEntry{
                wgpu.WGPUBindGroupLayoutEntry{
                    .binding = 0,
                    .visibility = wgpu.WGPUShaderStage_Compute,
                    .buffer = wgpu.WGPUBufferBindingLayout{
                        .type = wgpu.WGPUBufferBindingType_ReadOnlyStorage,
                    },
                },
                wgpu.WGPUBindGroupLayoutEntry{
                    .binding = 1,
                    .visibility = wgpu.WGPUShaderStage_Compute,
                    .buffer = wgpu.WGPUBufferBindingLayout{
                        .type = wgpu.WGPUBufferBindingType_Storage,
                    },
                },
            },
        },
    ) orelse {
        std.debug.print("Failed to create bind group layout\n", .{});
        return Error.FailedToCreateBindGroupLayout;
    };
    defer wgpu.wgpuBindGroupLayoutRelease(bind_group_layout);

    // Create bind group
    const bind_group: wgpu.WGPUBindGroup = wgpu.wgpuDeviceCreateBindGroup(
        device,
        &wgpu.WGPUBindGroupDescriptor{
            .layout = bind_group_layout,
            .entryCount = 2,
            .entries = &[_]wgpu.WGPUBindGroupEntry{
                wgpu.WGPUBindGroupEntry{
                    .binding = 0,
                    .buffer = input_buffer,
                    .offset = 0,
                    .size = buffer_size,
                },
                wgpu.WGPUBindGroupEntry{
                    .binding = 1,
                    .buffer = output_buffer,
                    .offset = 0,
                    .size = buffer_size,
                },
            },
        },
    ) orelse {
        std.debug.print("Failed to create bind group\n", .{});
        return Error.FailedToCreateBindGroup;
    };
    defer wgpu.wgpuBindGroupRelease(bind_group);

    // Create pipeline layout
    const pipeline_layout: wgpu.WGPUPipelineLayout = wgpu.wgpuDeviceCreatePipelineLayout(
        device,
        &wgpu.WGPUPipelineLayoutDescriptor{
            .bindGroupLayoutCount = 1,
            .bindGroupLayouts = &bind_group_layout,
        },
    ) orelse {
        std.debug.print("Failed to create pipeline layout\n", .{});
        return Error.FailedToCreatePipelineLayout;
    };
    defer wgpu.wgpuPipelineLayoutRelease(pipeline_layout);

    // Create compute pipeline
    const compute_pipeline: wgpu.WGPUComputePipeline = wgpu.wgpuDeviceCreateComputePipeline(
        device,
        &wgpu.WGPUComputePipelineDescriptor{
            .layout = pipeline_layout,
            .compute = wgpu.WGPUProgrammableStageDescriptor{
                .constantCount = 0,
                .constants = null,
                .entryPoint = "computeStuff",
                .module = shader,
            },
        },
    ) orelse {
        std.debug.print("Failed to create compute pipeline\n", .{});
        return Error.FailedToCreateComputePipeline;
    };
    defer wgpu.wgpuComputePipelineRelease(compute_pipeline);

    // Initialize a command encoder
    const command_encoder: wgpu.WGPUCommandEncoder = wgpu.wgpuDeviceCreateCommandEncoder(
        device,
        &wgpu.WGPUCommandEncoderDescriptor{},
    ) orelse {
        std.debug.print("Failed to create command encoder\n", .{});
        return Error.FailedToCreateCommandEncoder;
    };
    defer wgpu.wgpuCommandEncoderRelease(command_encoder);

    // Create compute pass
    const compute_pass_encoder: wgpu.WGPUComputePassEncoder = wgpu.wgpuCommandEncoderBeginComputePass(
        command_encoder,
        &wgpu.WGPUComputePassDescriptor{},
    ) orelse {
        std.debug.print("Failed to create compute pass encoder\n", .{});
        return Error.FailedToCreateComputePassEncoder;
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
    const command_buffer: wgpu.WGPUCommandBuffer = wgpu.wgpuCommandEncoderFinish(
        command_encoder,
        null,
    ) orelse {
        std.debug.print("Failed to create command buffer\n", .{});
        return Error.FailedToCreateCommandBuffer;
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

    std.time.sleep(1_000_000);

    wgpu.wgpuBufferMapAsync(map_buffer, wgpu.WGPUMapMode_Read, 0, buffer_size, onMap, null);
    defer wgpu.wgpuBufferUnmap(map_buffer);

    _ = wgpu.wgpuDevicePoll(device, 1, null);

    const buf: *[64]f32 = @ptrCast(@alignCast(wgpu.wgpuBufferGetMappedRange(map_buffer, 0, buffer_size)));

    std.debug.print("\n", .{});
    for (buf, 0..) |val, i| {
        std.debug.print("[{d: >2}] = {d: >3.0}", .{ i, val });

        if (i + 1 < buf.len) {
            std.debug.print(", ", .{});
        }

        if ((i + 1) % 8 == 0) {
            std.debug.print("\n", .{});
        }
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
