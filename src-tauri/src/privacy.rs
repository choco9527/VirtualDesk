#[derive(serde::Serialize)]
pub struct PermissionStatus {
    trusted: bool,
    prompt_shown: bool,
    message: Option<&'static str>,
}

impl PermissionStatus {
    fn new(trusted: bool, prompt_shown: bool, message: Option<&'static str>) -> Self {
        Self {
            trusted,
            prompt_shown,
            message,
        }
    }
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PrivacySettingsPane {
    Accessibility,
}

#[cfg(target_os = "macos")]
mod platform {
    use super::PermissionStatus;
    use std::{ffi::c_void, ptr};

    type Boolean = u8;
    type CFIndex = isize;
    type CFTypeRef = *const c_void;
    type CFStringRef = *const c_void;
    type CFDictionaryRef = *const c_void;

    #[link(name = "ApplicationServices", kind = "framework")]
    unsafe extern "C" {
        static kAXTrustedCheckOptionPrompt: CFStringRef;
        fn AXIsProcessTrusted() -> Boolean;
        fn AXIsProcessTrustedWithOptions(options: CFDictionaryRef) -> Boolean;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    unsafe extern "C" {
        static kCFBooleanTrue: CFTypeRef;
        static kCFTypeDictionaryKeyCallBacks: c_void;
        static kCFTypeDictionaryValueCallBacks: c_void;

        fn CFDictionaryCreate(
            allocator: CFTypeRef,
            keys: *const *const c_void,
            values: *const *const c_void,
            num_values: CFIndex,
            key_callbacks: *const c_void,
            value_callbacks: *const c_void,
        ) -> CFDictionaryRef;
        fn CFRelease(cf: CFTypeRef);
    }

    pub fn accessibility_status(prompt: bool) -> PermissionStatus {
        let trusted = if prompt {
            request_accessibility()
        } else {
            unsafe { AXIsProcessTrusted() != 0 }
        };

        PermissionStatus::new(
            trusted,
            prompt && !trusted,
            (!trusted).then_some(
                "Enable VirtualDesk in System Settings > Privacy & Security > Accessibility.",
            ),
        )
    }

    fn request_accessibility() -> bool {
        unsafe {
            let keys = [kAXTrustedCheckOptionPrompt as *const c_void];
            let values = [kCFBooleanTrue];
            let options = CFDictionaryCreate(
                ptr::null(),
                keys.as_ptr(),
                values.as_ptr(),
                1,
                &raw const kCFTypeDictionaryKeyCallBacks,
                &raw const kCFTypeDictionaryValueCallBacks,
            );
            if options.is_null() {
                return AXIsProcessTrusted() != 0;
            }

            let trusted = AXIsProcessTrustedWithOptions(options) != 0;
            CFRelease(options);
            trusted
        }
    }
}

#[cfg(not(target_os = "macos"))]
mod platform {
    use super::PermissionStatus;

    pub fn accessibility_status(_prompt: bool) -> PermissionStatus {
        PermissionStatus::new(
            false,
            false,
            Some("Accessibility permission is only supported on macOS."),
        )
    }
}

pub fn accessibility_status(prompt: bool) -> PermissionStatus {
    platform::accessibility_status(prompt)
}
