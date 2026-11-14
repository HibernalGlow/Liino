use liino_core::{BoundedRingBuffer, DeviceCapabilities, RoleMode};

fn main() {
    let caps = DeviceCapabilities::detect_current();
    let role = caps.resolve_role(RoleMode::Auto).expect("resolve role");
    let mut rb = BoundedRingBuffer::new(1024);
    for i in 0..4096u64 {
        rb.push_overwrite(i);
    }
    println!(
        "platform={} role={:?} ring_len={}/{}",
        caps.platform_name,
        role,
        rb.len(),
        rb.capacity()
    );
}
