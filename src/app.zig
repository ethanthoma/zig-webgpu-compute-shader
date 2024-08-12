const std = @import("std");
const assert = std.debug.assert;

const glfw3 = @cImport({
    @cInclude("glfw3.h");
    @cDefine("GLFW_EXPOSE_NATIVE_WAYLAND", {});
    @cInclude("glfw3native.h");
});

const wgpu = @cImport({
    @cInclude("wgpu.h");
});

const Error = error{
    FailedToInitializeGLFW,
    FailedToOpenWindow,
    FailedToCreateInstance,
    FailedToGetAdapter,
    FailedToGetDevice,
    FailedToGetQueue,
    FailedToGetWaylandDisplay,
    FailedToGetWaylandWindow,
};

pub const App = struct {
    const Self = @This();

    window: *glfw3.GLFWwindow,
    device: *wgpu.WGPUDevice,
    queue: *wgpu.WGPUQueue,
    surface: *wgpu.WGPUSurface,

    pub fn init() !Self {
        // Open window
        const retval = glfw3.glfwInit();
        if (retval == glfw3.GL_FALSE) {
            std.debug.print("Failed to initialize GLFW\n", .{});
            return Error.FailedToInitializeGLFW;
        }
        errdefer glfw3.glfwTerminate();

        std.debug.print("Opening window\n", .{});
        const window: *glfw3.GLFWwindow = glfw3.glfwCreateWindow(640, 480, "VOXEL", null, null) orelse {
            std.debug.print("Failed to open window\n", .{});
            return Error.FailedToOpenWindow;
        };
        errdefer glfw3.glfwDestroyWindow(window);

        glfw3.glfwWindowHint(glfw3.GLFW_CLIENT_API, glfw3.GLFW_NO_API);
        glfw3.glfwWindowHint(glfw3.GLFW_RESIZABLE, glfw3.GLFW_TRUE);

        // Create instance
        std.debug.print("Creating instance\n", .{});
        const instance: wgpu.WGPUInstance = wgpu.wgpuCreateInstance(&.{}) orelse {
            std.debug.print("Failed to create wgpu instance\n", .{});
            return Error.FailedToCreateInstance;
        };
        defer wgpu.wgpuInstanceRelease(instance);

        // Create surface
        std.debug.print("Creating surface\n", .{});
        var surface = try glfwGetWGPUSurface(instance, window);
        errdefer wgpu.wgpuSurfaceRelease(surface);

        // Get adpater
        std.debug.print("Get adpater\n", .{});
        const adapter: wgpu.WGPUAdapter = retval: {
            const options = wgpu.WGPURequestAdapterOptions{
                .nextInChain = null,
                .compatibleSurface = surface,
            };

            break :retval requestAdapterSync(instance, &options) orelse {
                std.debug.print("Failed to get adapter\n", .{});
                return Error.FailedToGetAdapter;
            };
        };
        errdefer wgpu.wgpuAdapterRelease(adapter);

        // Get device
        std.debug.print("Get device\n", .{});
        var device: wgpu.WGPUDevice = retval: {
            const descriptor = wgpu.WGPUDeviceDescriptor{
                .nextInChain = null,
                .label = "My Device",
                .requiredFeatureCount = 0,
                .requiredLimits = null,
                .defaultQueue = .{
                    .nextInChain = null,
                    .label = "The default queue",
                },
            };

            break :retval requestDeviceSync(adapter, &descriptor) orelse {
                std.debug.print("Failed to get adapter\n", .{});
                return Error.FailedToGetDevice;
            };
        };
        errdefer wgpu.wgpuDeviceRelease(device);

        std.debug.print("Get queue\n", .{});
        var queue: wgpu.WGPUQueue = retval: {
            if (wgpu.wgpuDeviceGetQueue(device)) |queue| {
                break :retval queue;
            } else {
                std.debug.print("Failed to get queue\n", .{});
                return Error.FailedToGetQueue;
            }
        };
        errdefer wgpu.wgpuQueueRelease(queue);

        glfw3.glfwMakeContextCurrent(window);
        glfw3.glfwShowWindow(window);

        return Self{
            .window = window,
            .device = &device,
            .queue = &queue,
            .surface = &surface,
        };
    }

    pub fn deinit(self: *Self) void {
        wgpu.wgpuQueueRelease(self.queue.*);
        wgpu.wgpuSurfaceRelease(self.surface.*);
        wgpu.wgpuDeviceRelease(self.device.*);
        glfw3.glfwDestroyWindow(self.window);
        glfw3.glfwTerminate();
    }

    pub fn run(self: *Self) void {
        glfw3.glfwPollEvents();
        _ = wgpu.wgpuDevicePoll(self.device.*, 0, null);
        glfw3.glfwSwapBuffers(self.window);
    }

    pub fn isRunning(self: *Self) bool {
        return glfw3.glfwWindowShouldClose(self.window) == glfw3.GL_FALSE;
    }
};

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

// wayland only
fn glfwGetWGPUSurface(instance: wgpu.WGPUInstance, window: *glfw3.GLFWwindow) !wgpu.WGPUSurface {
    const wayland_display: *glfw3.wl_display = glfw3.glfwGetWaylandDisplay() orelse {
        return Error.FailedToGetWaylandDisplay;
    };
    const wayland_surface: *glfw3.wl_surface = glfw3.glfwGetWaylandWindow(window) orelse {
        return Error.FailedToGetWaylandWindow;
    };

    const fromWaylandSurface = wgpu.WGPUSurfaceDescriptorFromWaylandSurface{
        .chain = .{
            .next = null,
            .sType = wgpu.WGPUSType_SurfaceDescriptorFromWaylandSurface,
        },
        .display = wayland_display,
        .surface = wayland_surface,
    };

    const surfaceDescriptor = wgpu.WGPUSurfaceDescriptor{
        .nextInChain = &fromWaylandSurface.chain,
        .label = null,
    };

    return wgpu.wgpuInstanceCreateSurface(instance, &surfaceDescriptor);
}
