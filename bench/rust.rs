// Unmodified original sensor modules, compiled directly at -Os and -O3.
#[path = "../src/sensors/mod.rs"]
mod sensors;
use std::io::Write;
use std::time::Instant;
#[repr(C)]
#[derive(Default)]
struct Timespec { sec: i64, nsec: i64 }
unsafe extern "C" { fn clock_gettime(id: i32, ts: *mut Timespec) -> i32; }
fn cpu_ns() -> u64 {
    let mut ts=Timespec::default();
    assert_eq!(unsafe{clock_gettime(2,&mut ts)},0);
    ts.sec as u64*1_000_000_000+ts.nsec as u64
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let n:u64=args[1].parse().unwrap();
    let io=args[2]=="write";
    let mut sensors=sensors::Sensors::discover(false);
    let mut buf=String::with_capacity(48);
    for _ in 0..100 { buf.clear();sensors.sample(&mut buf);buf.push('\n');std::hint::black_box(&buf); }
    let stdout=std::io::stdout();
    let mut out=stdout.lock();
    let begin=Instant::now();let cpu_begin=cpu_ns();
    let mut checksum=0u64;
    for _ in 0..n {
        buf.clear();sensors.sample(&mut buf);buf.push('\n');
        if io {out.write_all(buf.as_bytes()).unwrap();out.flush().unwrap();}
        else { let b=std::hint::black_box(buf.as_bytes());checksum+=b.len() as u64+b[0] as u64; }
    }
    let cpu=cpu_ns()-cpu_begin;let wall=begin.elapsed().as_nanos();
    eprintln!("{{\"wall_ns\":{wall},\"cpu_ns\":{cpu},\"checksum\":{checksum}}}");
}
