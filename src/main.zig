const std = @import("std");
const assert = std.debug.assert;

const wgpu = @cImport({
    @cInclude("wgpu.h");
});

const Error = error{
    FailedToCreateInstance,
    FailedToGetAdapter,
    FailedToGetDevice,
    FailedToCreateShaderModule,
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
    const queue: wgpu.WGPUQueue = wgpu.wgpuDeviceGetQueue(device);
    defer wgpu.wgpuQueueRelease(queue);

    // Load the compute shader
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpathZ("src/compute-shader.wgsl", &path_buffer);

    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const shader_source: [*c]u8 = @ptrCast(try file.readToEndAlloc(std.heap.page_allocator, 472));
    shader_source[471] = 0;

    const shader_module_descriptor = wgpu.WGPUShaderModuleDescriptor{
        .label = "compute-shader.wgsl",
        .nextInChain = @as(*wgpu.WGPUChainedStruct, @ptrCast(@constCast(&wgpu.WGPUShaderModuleWGSLDescriptor{
            .code = shader_source,
            .chain = wgpu.WGPUChainedStruct{
                .sType = wgpu.WGPUSType_ShaderModuleWGSLDescriptor,
            },
        }))),
    };

    const shader_module: wgpu.WGPUShaderModule = retval: {
        if (wgpu.wgpuDeviceCreateShaderModule(device, &shader_module_descriptor)) |shader_module| {
            break :retval shader_module;
        } else {
            std.debug.print("Failed to create shader module\n", .{});
            return Error.FailedToCreateShaderModule;
        }
    };
    defer wgpu.wgpuShaderModuleRelease(shader_module);

    // Create input and output buffers
    var input_data: [64]f32 = undefined;
    for (input_data, 0..) |_, i| {
        input_data[i] = @floatFromInt(i + 1);
    }

    const buffer_size = @sizeOf([64]f32);

    const input_buffer_descriptor = wgpu.WGPUBufferDescriptor{
        .usage = wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopyDst,
        .size = buffer_size,
        .mappedAtCreation = 0,
    };
    const input_buffer = wgpu.wgpuDeviceCreateBuffer(device, &input_buffer_descriptor);
    defer wgpu.wgpuBufferRelease(input_buffer);

    const output_buffer_descriptor = wgpu.WGPUBufferDescriptor{
        .usage = wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopySrc,
        .size = buffer_size,
        .mappedAtCreation = 0,
    };
    const output_buffer = wgpu.wgpuDeviceCreateBuffer(device, &output_buffer_descriptor);
    defer wgpu.wgpuBufferRelease(output_buffer);

    const map_buffer_descriptor = wgpu.WGPUBufferDescriptor{
        .usage = wgpu.WGPUBufferUsage_CopyDst | wgpu.WGPUBufferUsage_MapRead,
        .size = buffer_size,
        .mappedAtCreation = 0,
    };
    const map_buffer = wgpu.wgpuDeviceCreateBuffer(device, &map_buffer_descriptor);
    defer wgpu.wgpuBufferRelease(map_buffer);

    // Create bind group layout and bind group
    const bind_group_layout_descriptor = wgpu.WGPUBindGroupLayoutDescriptor{
        .entryCount = 2,
        .entries = &[_]wgpu.WGPUBindGroupLayoutEntry{
            wgpu.WGPUBindGroupLayoutEntry{ .binding = 0, .visibility = wgpu.WGPUShaderStage_Compute, .buffer = wgpu.WGPUBufferBindingLayout{ .type = wgpu.WGPUBufferBindingType_ReadOnlyStorage } },
            wgpu.WGPUBindGroupLayoutEntry{ .binding = 1, .visibility = wgpu.WGPUShaderStage_Compute, .buffer = wgpu.WGPUBufferBindingLayout{ .type = wgpu.WGPUBufferBindingType_Storage } },
        },
    };
    const bind_group_layout = wgpu.wgpuDeviceCreateBindGroupLayout(device, &bind_group_layout_descriptor);
    defer wgpu.wgpuBindGroupLayoutRelease(bind_group_layout);

    const bind_group_descriptor = wgpu.WGPUBindGroupDescriptor{
        .layout = bind_group_layout,
        .entryCount = 2,
        .entries = &[_]wgpu.WGPUBindGroupEntry{
            wgpu.WGPUBindGroupEntry{ .binding = 0, .buffer = input_buffer, .offset = 0, .size = buffer_size },
            wgpu.WGPUBindGroupEntry{ .binding = 1, .buffer = output_buffer, .offset = 0, .size = buffer_size },
        },
    };
    const bind_group = wgpu.wgpuDeviceCreateBindGroup(device, &bind_group_descriptor);
    defer wgpu.wgpuBindGroupRelease(bind_group);

    // Create pipeline layout
    const pipeline_layout_descriptor = wgpu.WGPUPipelineLayoutDescriptor{
        .bindGroupLayoutCount = 1,
        .bindGroupLayouts = &bind_group_layout,
    };
    const pipeline_layout = wgpu.wgpuDeviceCreatePipelineLayout(device, &pipeline_layout_descriptor);
    defer wgpu.wgpuPipelineLayoutRelease(pipeline_layout);

    // Create compute pipeline
    const compute_pipeline_descriptor = wgpu.WGPUComputePipelineDescriptor{
        .layout = pipeline_layout,
        .compute = wgpu.WGPUProgrammableStageDescriptor{
            .constantCount = 0,
            .constants = null,
            .entryPoint = "computeStuff",
            .module = shader_module,
        },
    };
    const compute_pipeline = wgpu.wgpuDeviceCreateComputePipeline(device, &compute_pipeline_descriptor);
    defer wgpu.wgpuComputePipelineRelease(compute_pipeline);

    // Initialize a command encoder
    const command_encoder_descriptor = wgpu.WGPUCommandEncoderDescriptor{};
    const command_encoder = wgpu.wgpuDeviceCreateCommandEncoder(device, &command_encoder_descriptor);
    defer wgpu.wgpuCommandEncoderRelease(command_encoder);

    // Create compute pass
    const compute_pass_descriptor = wgpu.WGPUComputePassDescriptor{};
    const compute_pass = wgpu.wgpuCommandEncoderBeginComputePass(command_encoder, &compute_pass_descriptor);

    // Use compute pass
    wgpu.wgpuComputePassEncoderSetPipeline(compute_pass, compute_pipeline);
    wgpu.wgpuComputePassEncoderSetBindGroup(compute_pass, 0, bind_group, 0, null);

    const invocationCount: u32 = buffer_size / @sizeOf(f32);
    const workgroupSize: u32 = 32;
    const workgroupCount: u32 = (invocationCount + workgroupSize - 1) / workgroupSize;
    wgpu.wgpuComputePassEncoderDispatchWorkgroups(compute_pass, workgroupCount, 1, 1);

    // Finalize compute pass
    wgpu.wgpuComputePassEncoderEnd(compute_pass);

    // Before encoder finish
    wgpu.wgpuCommandEncoderCopyBufferToBuffer(command_encoder, output_buffer, 0, map_buffer, 0, buffer_size);

    // Encode commands
    const command_buffer = wgpu.wgpuCommandEncoderFinish(command_encoder, null);
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
