package main
import vk "../vulkan_gen/vulkan/"
import sdl "../deps/odin-sdl2/"

import "core:fmt"
import "core:runtime"
import "core:log"
import "core:strings"

/* TODO List
1) Callback message handling to different log levels and filtering via a global var
2) Use queue family properties check to select the physical device as well as checking desired dvice extensions.
   annnnddd checking swapchain requirements
*/

VkGetInstanceProcAddr :: proc(instance: vk.Instance, pName: cstring) -> rawptr;

VkGetInstanceProc : VkGetInstanceProcAddr;

VkInstance : vk.Instance = nil;

GlobalLog : log.Logger;

VkSetProcAddress :: proc(p: rawptr, name: cstring) {
    (cast(^rawptr)(p))^  = VkGetInstanceProc(VkInstance, name);
}

VkDebugCallback : vk.ProcDebugUtilsMessengerCallbackEXT : proc"stdcall"(message_severity : vk.DebugUtilsMessageSeverityFlagsEXT,
                                                                        message_type : vk.DebugUtilsMessageTypeFlagsEXT,
                                                                        callback_data : ^vk.DebugUtilsMessengerCallbackDataEXT,
                                                                        user_data : rawptr) -> b32 {
    context = runtime.default_context();
    context.logger = GlobalLog;
    log.info("Validation layer: ", callback_data.pMessage);
    // log.info("Validation layer: ", callback_data.pMessage);
    // NOTE: Couldn't get vk.FALSE to return here instead. Didn't want to cast from the untyped integer
    return false;
}

VkInstanceCreationDestructionDebugCallback : vk.ProcDebugUtilsMessengerCallbackEXT : proc"stdcall"(message_severity : vk.DebugUtilsMessageSeverityFlagsEXT,
                                                                                                   message_type : vk.DebugUtilsMessageTypeFlagsEXT,
                                                                                                   callback_data : ^vk.DebugUtilsMessengerCallbackDataEXT,
                                                                                                   user_data : rawptr) -> b32 {
    context = runtime.default_context();
    context.logger = GlobalLog;
    log.info("Validation layer: ", callback_data.pMessage);
    // log.info("Validation layer: ", callback_data.pMessage);
    // NOTE: Couldn't get vk.FALSE to return here instead. Didn't want to cast from the untyped integer
    return false;
}

main :: proc() {
    // Build the logger
    GlobalLog = log.create_console_logger();
    context.logger = GlobalLog;
    log.info("Logger initialized");
    
    // Do SDL2
    // Any reason to not init everything?
    sdl.init(sdl.Init_Flags.Everything);
    vk_load_lib_res := sdl.vulkan_load_library(nil);
    if vk_load_lib_res != 0 {
        log.fatal("Unable to load vulkan lib!");
        log.fatal(sdl.get_error());
        return;
    }
    
    window := sdl.create_window("Nito",
                                i32(sdl.Window_Pos.Centered), i32(sdl.Window_Pos.Centered),
                                1920, 1080,
                                sdl.Window_Flags.Vulkan | sdl.Window_Flags.Shown);
    
    vk_proc_addr := sdl.vulkan_get_gk_get_instance_proc_addr();
    if vk_proc_addr == nil {
        log.fatal("Unable to get vk_proc_addr!");
        return;
    }
    VkGetInstanceProc = cast(VkGetInstanceProcAddr)vk_proc_addr;
    vk.load_proc_addresses(VkSetProcAddress);
    
    if window == nil {
        log.fatal("Unable to create sdl window!");
        log.fatal(sdl.get_error());
        return;
    }
    
    vk_extensions_count : u32;
    // NOTE: Calling get_instance_extensions once to get the count only. Then the second time to fill in the data
    vk_get_instance_extensions_res := sdl.vulkan_get_instance_extensions(window, &vk_extensions_count, nil);
    vk_extensions := make([dynamic]cstring, vk_extensions_count);
    vk_get_instance_extensions_res = sdl.vulkan_get_instance_extensions(window, &vk_extensions_count, &vk_extensions[0]);
    if vk_get_instance_extensions_res == 0 {
        log.fatal("    Failed to get Vulkan instance extensions!");
        log.fatal(sdl.get_error());
        return;
    }
    log.info("Found", vk_extensions_count, "Vulkan extensions:");
    for i in 0..<vk_extensions_count {
        log.info("    Vulkan Extension: ", vk_extensions[i]);
    }
    
    app_info : vk.ApplicationInfo;
    app_info.sType = vk.StructureType.APPLICATION_INFO;
    app_info.pApplicationName = "Nito";
    app_info.applicationVersion = vk.MAKE_VERSION(1, 0, 0);
    app_info.pEngineName = "No Engine";
    app_info.engineVersion = vk.MAKE_VERSION(1, 0, 0);
    app_info.apiVersion = vk.API_VERSION_1_0;
    
    instance_create_info : vk.InstanceCreateInfo;
    instance_create_info.sType = vk.StructureType.INSTANCE_CREATE_INFO;
    instance_create_info.pApplicationInfo = &app_info;
    instance_create_info.enabledLayerCount = 0;
    
    enabled_layers := make([dynamic]cstring);
    if ODIN_DEBUG {
        vk_layer_count : u32;
        vk.EnumerateInstanceLayerProperties(&vk_layer_count, nil);
        vk_layer_props := make([dynamic]vk.LayerProperties, vk_layer_count);
        vk.EnumerateInstanceLayerProperties(&vk_layer_count, &vk_layer_props[0]);
        log.info("Found", vk_layer_count, "available Vulkan validation layers.");
        
        desired_layers := make([dynamic]string);
        append(&desired_layers, "VK_LAYER_KHRONOS_validation");
        for i in 0..<len(desired_layers) {
            desired_layer := desired_layers[i];
            found := false;
            for j in 0..<vk_layer_count {
                curr_layer := string(cstring(&vk_layer_props[j].layerName[0]));
                if desired_layer == curr_layer {
                    append(&enabled_layers, strings.clone_to_cstring(desired_layer));
                    found = true;
                    break;
                }
            }
            if !found do log.warn("Could not find desired validation layer ", desired_layer);
        }
        log.info("Available Vulkan Validation Layers:");
        for i in 0..<vk_layer_count {
            layer_name := string(vk_layer_props[i].layerName[:]);
            log.info("    ", layer_name);
        }
        
        instance_create_info.enabledLayerCount = u32(len(enabled_layers));
        instance_create_info.ppEnabledLayerNames = &enabled_layers[0];
        
        append(&vk_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME);
        vk_extensions_count += 1;
        
        // NOTE: Need a separate debug message callback just for the instance creation and estruction vulkan calls...
        debug_messenger_info : vk.DebugUtilsMessengerCreateInfoEXT;
        debug_messenger_info.sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
        severity_flags : vk.DebugUtilsMessageSeverityFlagsEXT;
        // severity_flags = {.VERBOSE, .INFO, .WARNING, .ERROR};
        severity_flags = {.WARNING, .ERROR};
        type_flags : vk.DebugUtilsMessageTypeFlagsEXT;
        type_flags = {.GENERAL, .VALIDATION, .PERFORMANCE};
        debug_messenger_info.messageSeverity = severity_flags;
        debug_messenger_info.messageType = type_flags;
        debug_messenger_info.pfnUserCallback = VkInstanceCreationDestructionDebugCallback;
        debug_messenger_info.pUserData = nil;
        
        instance_create_info.pNext = &debug_messenger_info;
    }    
    instance_create_info.enabledExtensionCount = vk_extensions_count;
    instance_create_info.ppEnabledExtensionNames = &vk_extensions[0];
    
    vk_instance_create_res := vk.CreateInstance(&instance_create_info, nil, &VkInstance);
    if vk_instance_create_res != vk.Result.SUCCESS {
        log.fatal("Failed to create Vulkan Instance!");
        return;
    }
    vk.load_proc_addresses(VkSetProcAddress);
    
    debug_messenger : vk.DebugUtilsMessengerEXT;
    if ODIN_DEBUG {
        debug_messenger_info : vk.DebugUtilsMessengerCreateInfoEXT;
        debug_messenger_info.sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
        severity_flags : vk.DebugUtilsMessageSeverityFlagsEXT;
        // severity_flags = {.VERBOSE, .INFO, .WARNING, .ERROR};
        severity_flags = {.WARNING, .ERROR};
        type_flags : vk.DebugUtilsMessageTypeFlagsEXT;
        type_flags = {.GENERAL, .VALIDATION, .PERFORMANCE};
        debug_messenger_info.messageSeverity = severity_flags;
        debug_messenger_info.messageType = type_flags;
        debug_messenger_info.pfnUserCallback = VkDebugCallback;
        debug_messenger_info.pUserData = nil;
        
        debug_messenger_create_res := vk.CreateDebugUtilsMessengerEXT(VkInstance, &debug_messenger_info, nil, &debug_messenger);
        if debug_messenger_create_res != vk.Result.SUCCESS {
            log.error("Unable to create the debug messenger!");
        } else {
            log.info("Created the debug messenger");
        }
    }
    
    surface : vk.SurfaceKHR;
    create_surface_res := sdl.vulkan_create_surface(window, VkInstance, &surface);
    if create_surface_res == sdl.Bool.False {
        log.fatal("Failed to create Vulkan surface!");
        return;
    }
    log.info("Created Vulkan Surface!");
    
    physical_device_count : u32;
    vk.EnumeratePhysicalDevices(VkInstance, &physical_device_count, nil);
    if physical_device_count <= 0 {
        log.fatal("Failed to find any devices with Vulkan support!");
        return;
    }
    physical_devices := make([dynamic]vk.PhysicalDevice, physical_device_count);
    vk.EnumeratePhysicalDevices(VkInstance, &physical_device_count, &physical_devices[0]);
    selected_device_index := -1;
    log.info("Found", physical_device_count, "physical devices");
    for i in 0..<physical_device_count {
        device_props : vk.PhysicalDeviceProperties;
        vk.GetPhysicalDeviceProperties(physical_devices[i], &device_props);
        device_features : vk.PhysicalDeviceFeatures;
        vk.GetPhysicalDeviceFeatures(physical_devices[i], &device_features);
        
        log.info("Device", i);
        // TODO: Better heuristic than selecting the first device with a discrete GPU
        if selected_device_index < 0 && device_props.deviceType == vk.PhysicalDeviceType.DISCRETE_GPU {
            log.info("    !----SELECTED THIS DEVICE----!");
            selected_device_index = int(i);
        }
        log.info("    Properties:", device_props);
        log.info("    Features:", device_features);
        
    }
    if selected_device_index < 0 {
        log.fatal("Failed to find a discrete GPU!");
        return;
    }
    selected_device := physical_devices[selected_device_index];
    
    queue_family_count : u32;
    vk.GetPhysicalDeviceQueueFamilyProperties(selected_device, &queue_family_count, nil);
    if queue_family_count <= 0 {
        log.fatal("Failed to find queue families for device", selected_device);
        return;
    }
    queue_families := make([dynamic]vk.QueueFamilyProperties, queue_family_count);
    vk.GetPhysicalDeviceQueueFamilyProperties(selected_device, &queue_family_count, &queue_families[0]);
    graphics_queue_family_index : u32;
    present_queue_family_index : u32;
    found_graphics_queue_family := false;
    found_present_queue_family := false;
    log.info("Found", queue_family_count, "queue families for selected device.");
    for i in 0..<queue_family_count {
        queue_family := queue_families[i];
        present_support : b32 = false;
        vk.GetPhysicalDeviceSurfaceSupportKHR(selected_device, i, surface, &present_support);
        if present_support && vk.QueueFlag.GRAPHICS in queue_family.queueFlags {
            log.info("    !----SELECTED THIS QUEUE FAMILY FOR GRAPHICS AND PRESENT----!");
            log.info("   ", queue_families[i]);
            graphics_queue_family_index = i; 
            present_queue_family_index = i;
            found_graphics_queue_family = true;
            found_present_queue_family = true;
            for j in (i+1)..<queue_family_count {
                log.info("   ", queue_families[j]);
            }
            break;
        }
        if !found_present_queue_family && bool(present_support) {
            log.info("    !----SELECTED THIS QUEUE FAMILY FOR PRESENT----!");
            present_queue_family_index = i;
            found_present_queue_family = true;
        }
        if !found_graphics_queue_family && vk.QueueFlag.GRAPHICS in queue_family.queueFlags {
            log.info("    !----SELECTED THIS QUEUE FAMILY FOR GRAPHICS----!");
            graphics_queue_family_index = i; 
            found_graphics_queue_family = true;
        }
        log.info("   ", queue_families[i]);
    }
    if !(found_graphics_queue_family) {
        log.fatal("Did not find a queue family with graphics support");
        return;
    }
    if !(found_present_queue_family) {
        log.fatal("Did not find a queue family with present support");
        return;
    }
    
    device_extension_count : u32;
    vk.EnumerateDeviceExtensionProperties(selected_device, nil, &device_extension_count, nil);
    device_extensions := make([dynamic]vk.ExtensionProperties, device_extension_count);
    vk.EnumerateDeviceExtensionProperties(selected_device, nil, &device_extension_count, &device_extensions[0]);
    found_swapchain_device_extension := false;
    enabled_device_extensions : [dynamic]cstring;
    log.info("Found", device_extension_count, "device extensions");
    for i in 0..<device_extension_count {
        extension := device_extensions[i];
        extension_name := cstring(&extension.extensionName[0]);
        log.info("    ", extension_name);
        if extension_name == vk.KHR_SWAPCHAIN_EXTENSION_NAME {
            found_swapchain_device_extension = true;
            append(&enabled_device_extensions, vk.KHR_SWAPCHAIN_EXTENSION_NAME);
        }
    }
    if !found_swapchain_device_extension {
        log.fatal("Did not find device extension", vk.KHR_SWAPCHAIN_EXTENSION_NAME);
        return;
    }
   
    queue_priority : f32 = 1.0;
    queue_create_infos : [dynamic]vk.DeviceQueueCreateInfo;
    
    graphics_queue_create_info : vk.DeviceQueueCreateInfo;
    graphics_queue_create_info.sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO;
    graphics_queue_create_info.queueFamilyIndex = graphics_queue_family_index;
    graphics_queue_create_info.queueCount = 1;
    graphics_queue_create_info.pQueuePriorities = &queue_priority;
    append(&queue_create_infos, graphics_queue_create_info);
    
    present_queue_create_info : vk.DeviceQueueCreateInfo;
    if present_queue_family_index != graphics_queue_family_index {
        present_queue_create_info.sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO;
        present_queue_create_info.queueFamilyIndex = present_queue_family_index;
        present_queue_create_info.queueCount = 1;
        present_queue_create_info.pQueuePriorities = &queue_priority;
        append(&queue_create_infos, present_queue_create_info);
    }
    
    device_features : vk.PhysicalDeviceFeatures;
    
    device_create_info : vk.DeviceCreateInfo;
    device_create_info.sType = vk.StructureType.DEVICE_CREATE_INFO;
    device_create_info.pQueueCreateInfos = &queue_create_infos[0];
    device_create_info.queueCreateInfoCount = u32(len(queue_create_infos));
    device_create_info.pEnabledFeatures = &device_features;
    device_create_info.enabledExtensionCount = u32(len(enabled_device_extensions));
    device_create_info.ppEnabledExtensionNames = &enabled_device_extensions[0];
    device_create_info.enabledLayerCount = 0;
    // NOTE: Latest implementation of Vulkan no longer has device specific validation layers so this is likely ignored
    if ODIN_DEBUG {
        device_create_info.enabledLayerCount = u32(len(enabled_layers));
        device_create_info.ppEnabledLayerNames = &enabled_layers[0];
    }
    
    logical_device : vk.Device;
    device_create_res := vk.CreateDevice(selected_device, &device_create_info, nil, &logical_device);
    if device_create_res != vk.Result.SUCCESS {
        log.fatal("Failed to create logical device!");
        return;
    }
    log.info("Created logical device!");
    
    surface_capabilities : vk.SurfaceCapabilitiesKHR;
    get_surface_caps_res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(selected_device, surface, &surface_capabilities);
    if get_surface_caps_res != vk.Result.SUCCESS {
        log.fatal("Unable to get selected physical device surface capabilities");
        return;
    }
    surface_formats_count : u32;
    vk.GetPhysicalDeviceSurfaceFormatsKHR(selected_device, surface, &surface_formats_count, nil);
    if surface_formats_count <= 0 {
        log.fatal("Failed to find surface formats");
        return;
    }
    surface_formats := make([dynamic]vk.SurfaceFormatKHR, surface_formats_count);
    vk.GetPhysicalDeviceSurfaceFormatsKHR(selected_device, surface, &surface_formats_count, &surface_formats[0]);
    present_modes_count : u32;
    vk.GetPhysicalDeviceSurfacePresentModesKHR(selected_device, surface, &present_modes_count, nil);
    if present_modes_count <= 0 {
        log.fatal("Failed to find present modes");
        return;
    }
    present_modes := make([dynamic]vk.PresentModeKHR, present_modes_count);
    vk.GetPhysicalDeviceSurfacePresentModesKHR(selected_device, surface, &present_modes_count, &present_modes[0]);
    
    swap_surface_format : vk.SurfaceFormatKHR;
    found_desired_swap_surface_format := false;
    for i in 0..<surface_formats_count {
        format := surface_formats[i];
        if format.format == vk.Format.B8G8R8A8_SRGB && format.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR {
            swap_surface_format = format;
            found_desired_swap_surface_format = true;
        }
    }
    if !found_desired_swap_surface_format {
        log.warn("Did not find desired swap surface format. Defaulting to the first available format.");
        swap_surface_format = surface_formats[0];
    }
    
    present_mode : vk.PresentModeKHR;
    found_desired_present_mode := false;
    for i in 0..<present_modes_count {
        curr_present_mode := present_modes[i];
        if curr_present_mode == vk.PresentModeKHR.MAILBOX {
            present_mode = curr_present_mode;
            found_desired_present_mode = true;
        }
    }
    if !found_desired_present_mode {
        log.warn("Did not find desired present mode. Defaulting to FIFO.");
        present_mode = vk.PresentModeKHR.FIFO;
    }
    
    swap_extent : vk.Extent2D;
    if surface_capabilities.currentExtent.width != 0xFFFFFFFF {
        swap_extent = surface_capabilities.currentExtent;
    } else {
        vk_drawable_width, vk_drawable_height : i32;
        sdl.vulkan_get_drawable_size(window, &vk_drawable_width, &vk_drawable_height);
        log.info("Vulkan drawable size: ", vk_drawable_width, " ", vk_drawable_height);
        
        swap_extent.width = max(surface_capabilities.minImageExtent.width,
                                min(surface_capabilities.maxImageExtent.width, u32(vk_drawable_width)));
        swap_extent.height = max(surface_capabilities.minImageExtent.height,
                                 min(surface_capabilities.maxImageExtent.height, u32(vk_drawable_height)));
    }
    log.info("Swap Extent:", swap_extent);
    log.info("Swap Surface Format:", swap_surface_format);
    log.info("Present Mode:", present_mode);
    
    desired_swap_chain_image_count := surface_capabilities.minImageCount + 1;
    // NOTE: maxImageCount of zero is a special case meaning there is no maximum.
    if surface_capabilities.maxImageCount > 0 && desired_swap_chain_image_count > surface_capabilities.maxImageCount {
        desired_swap_chain_image_count = surface_capabilities.maxImageCount;
    }
    log.info("Desired swap chain image count:", desired_swap_chain_image_count);
    
    
    old_swap_chain : vk.SwapchainKHR;
    swap_chain_create_info : vk.SwapchainCreateInfoKHR;
    swap_chain_create_info.sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR;
    swap_chain_create_info.surface = surface;
    swap_chain_create_info.minImageCount = desired_swap_chain_image_count;
    swap_chain_create_info.imageFormat = swap_surface_format.format;
    swap_chain_create_info.imageColorSpace = swap_surface_format.colorSpace;
    swap_chain_create_info.imageExtent = swap_extent;
    swap_chain_create_info.imageArrayLayers = 1;
    swap_chain_create_info.imageUsage = {.COLOR_ATTACHMENT};
    if graphics_queue_family_index != present_queue_family_index {
        swap_chain_create_info.imageSharingMode = vk.SharingMode.CONCURRENT;
        swap_chain_create_info.queueFamilyIndexCount = 2;
        queue_family_indices : [2]u32 = {graphics_queue_family_index, present_queue_family_index};
        swap_chain_create_info.pQueueFamilyIndices = &queue_family_indices[0];
    } else {
        swap_chain_create_info.imageSharingMode = vk.SharingMode.EXCLUSIVE;
        swap_chain_create_info.queueFamilyIndexCount = 0; // Optional
        swap_chain_create_info.pQueueFamilyIndices = nil; // Optional
    }
    swap_chain_create_info.preTransform = surface_capabilities.currentTransform;
    swap_chain_create_info.compositeAlpha = {.OPAQUE};
    swap_chain_create_info.presentMode = present_mode;
    swap_chain_create_info.clipped = true;
    swap_chain_create_info.oldSwapchain = old_swap_chain; 
    swap_chain : vk.SwapchainKHR;
    swap_chain_create_res := vk.CreateSwapchainKHR(logical_device, &swap_chain_create_info, nil, &swap_chain);
    if swap_chain_create_res != vk.Result.SUCCESS {
        log.fatal("Failed to create swap chain");
        return;
    }
    log.info("Created the swap chain");
    
    swap_chain_image_count : u32;
    vk.GetSwapchainImagesKHR(logical_device, swap_chain, &swap_chain_image_count, nil);
    swap_chain_images := make([dynamic]vk.Image, swap_chain_image_count);
    vk.GetSwapchainImagesKHR(logical_device, swap_chain, &swap_chain_image_count, &swap_chain_images[0]);
    
    swap_chain_image_format := swap_surface_format.format;
    
    graphics_queue : vk.Queue;
    vk.GetDeviceQueue(logical_device, graphics_queue_family_index, 0, &graphics_queue);
    present_queue : vk.Queue;
    vk.GetDeviceQueue(logical_device, present_queue_family_index, 0, &present_queue);
    
    vk.DestroySwapchainKHR(logical_device, swap_chain, nil);
    vk.DestroyDevice(logical_device, nil);
    vk.DestroySurfaceKHR(VkInstance, surface, nil);
    if ODIN_DEBUG {
        vk.DestroyDebugUtilsMessengerEXT(VkInstance, debug_messenger, nil);
    }
    vk.DestroyInstance(VkInstance, nil);
    
    sdl.quit();
    log.info("PROGRAM END");
}