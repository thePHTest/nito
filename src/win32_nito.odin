package main
import vk "../vulkan_gen/vulkan/"
import sdl "../deps/odin-sdl2/"

import "core:fmt"
import "core:runtime"
import "core:log"
import "core:strings"

/* TODO List
1) How to use the GlobalLog (console logger) in the VkDebugCallbacks (issues because these are "stdcall" procs)
2) Callback message handling to different log levels and filtering via a global var
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
    fmt.println("Validation layer: ", callback_data.pMessage);
    // log.info("Validation layer: ", callback_data.pMessage);
    // NOTE: Couldn't get vk.FALSE to return here instead. Didn't want to cast from the untyped integer
    return false;
}

VkInstanceCreationDestructionDebugCallback : vk.ProcDebugUtilsMessengerCallbackEXT : proc"stdcall"(message_severity : vk.DebugUtilsMessageSeverityFlagsEXT,
                                                                                                   message_type : vk.DebugUtilsMessageTypeFlagsEXT,
                                                                                                   callback_data : ^vk.DebugUtilsMessengerCallbackDataEXT,
                                                                                                   user_data : rawptr) -> b32 {
    context = runtime.default_context();
    fmt.println("Validation layer: ", callback_data.pMessage);
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
    
    vk_app_info : vk.ApplicationInfo;
    vk_app_info.sType = vk.StructureType.APPLICATION_INFO;
    vk_app_info.pApplicationName = "Nito";
    vk_app_info.applicationVersion = vk.MAKE_VERSION(1, 0, 0);
    vk_app_info.pEngineName = "No Engine";
    vk_app_info.engineVersion = vk.MAKE_VERSION(1, 0, 0);
    vk_app_info.apiVersion = vk.API_VERSION_1_0;
    
    vk_create_info : vk.InstanceCreateInfo;
    vk_create_info.sType = vk.StructureType.INSTANCE_CREATE_INFO;
    vk_create_info.pApplicationInfo = &vk_app_info;
    vk_create_info.enabledLayerCount = 0;
    if ODIN_DEBUG {
        vk_layer_count : u32;
        vk.EnumerateInstanceLayerProperties(&vk_layer_count, nil);
        vk_layer_props := make([dynamic]vk.LayerProperties, vk_layer_count);
        vk.EnumerateInstanceLayerProperties(&vk_layer_count, &vk_layer_props[0]);
        log.info("Found", vk_layer_count, "available Vulkan validation layers.");
        
        desired_layers := make([dynamic]string);
        enabled_layers := make([dynamic]cstring);
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
        
        vk_create_info.enabledLayerCount = u32(len(enabled_layers));
        vk_create_info.ppEnabledLayerNames = &enabled_layers[0];
        
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
        
        vk_create_info.pNext = &debug_messenger_info;
    }    
    vk_create_info.enabledExtensionCount = vk_extensions_count;
    vk_create_info.ppEnabledExtensionNames = &vk_extensions[0];
    
    vk_instance_create_res := vk.CreateInstance(&vk_create_info, nil, &VkInstance);
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
    
    vk_surface : vk.SurfaceKHR;
    create_surface_res := sdl.vulkan_create_surface(window, VkInstance, &vk_surface);
    if create_surface_res == sdl.Bool.False {
        log.fatal("Failed to create Vulkan surface!");
        return;
    }
    log.info("Created Vulkan Surface!");
    
    vk_drawable_width, vk_drawable_height : i32;
    sdl.vulkan_get_drawable_size(window, &vk_drawable_width, &vk_drawable_height);
    log.info("Vulkan drawable size: ", vk_drawable_width, " ", vk_drawable_height);
    
    if ODIN_DEBUG {
        vk.DestroyDebugUtilsMessengerEXT(VkInstance, debug_messenger, nil);
    }
    vk.DestroyInstance(VkInstance, nil);
    
    sdl.quit();
    log.info("PROGRAM END");
}