use std::io::{self, BufRead};
fn main(){
 for line in io::stdin().lock().lines(){
  let line=line.unwrap();
  let raw:Vec<u8>=(0..line.len()).step_by(2).map(|i|u8::from_str_radix(&line[i..i+2],16).unwrap()).collect();
  let Ok(s)=std::str::from_utf8(&raw) else {println!("invalid");continue};
  let s=s.trim();
  for b in s.as_bytes(){print!("{b:02x}");}
  let u=s.parse::<u64>().map(|n|n.to_string()).unwrap_or("invalid".into());
  let i=s.parse::<i32>().map(|n|n.to_string()).unwrap_or("invalid".into());
  println!("|{u}|{i}");
 }
}
