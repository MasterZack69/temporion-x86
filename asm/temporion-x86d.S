/* SPDX-License-Identifier: AGPL-3.0-only
 * Linux x86-64 / System V ABI. GNU assembler, Intel syntax.
 * All daemon logic is assembly; libc supplies filesystem/dynamic-loader ABI.
 */
.intel_syntax noprefix
.macro ENTER bytes=0
 push rbp
 mov rbp, rsp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp, (\bytes + 8)
.endm
.macro LEAVE bytes=0
 add rsp, (\bytes + 8)
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret
.endm
.section .rodata
hw_pattern: .asciz "/sys/class/hwmon/*"
pci_pattern: .asciz "/sys/bus/pci/devices/*"
name_fmt: .asciz "%s/name"
label_fmt: .asciz "%s/temp*_label"
input_fmt: .asciz "%.*s_input"
device_fmt: .asciz "%s/device"
model_fmt: .asciz "/sys/class/nvme/nvme%u/model"
vendor_fmt: .asciz "%s/vendor"
class_fmt: .asciz "%s/class"
status_fmt: .asciz "%s/power/runtime_status"
cpu_name: .asciz "k10temp"
disk_name: .asciz "nvme"
cpu_label: .asciz "Tctl"
disk_label: .asciz "Composite"
suspended: .asciz "suspended"
unknown: .asciz "unknown"
node_fmt: .asciz "nvme%u"
node_unknown: .asciz "nvme?"
env_interval: .asciz "TEMPORION_X86_INTERVAL_MS"
env_always: .asciz "TEMPORION_X86_GPU_ALWAYS"
lib1: .asciz "libnvidia-ml.so.1"
lib2: .asciz "libnvidia-ml.so"
lib3: .asciz "/run/opengl-driver/lib/libnvidia-ml.so.1"
sym_init: .asciz "nvmlInit_v2"
sym_handle: .asciz "nvmlDeviceGetHandleByIndex_v2"
sym_temp: .asciz "nvmlDeviceGetTemperature"
summary_fmt: .asciz "temporion-x86d: cpu=%s, gpu=%s, disks=%zu\n"
summary_disk: .asciz "temporion-x86d:   disk%zu = %s (%s)\n"
cpu_yes: .asciz "k10temp/Tctl"
cpu_no: .asciz "not found"
gpu_no: .asciz "unavailable"
gpu_yes: .asciz "nvml"
gpu_gate: .asciz "nvml (suspend-aware)"
.section .bss
.align 8
cpu_path: .zero 8
runtime_path: .zero 8
lib_handle: .zero 8
init_fn: .zero 8
handle_fn: .zero 8
temp_fn: .zero 8
gpu_device: .zero 8
session_ready: .zero 4
gpu_always: .zero 4
disks: .zero 8
disk_count: .zero 8
output: .zero 8
output_size: .zero 8
interval: .zero 16
attr: .zero 257
.section .text
/* Validate UTF-8, trim exactly Rust str::trim's Unicode White_Space set.
 * rdi=data, rsi=len -> rax=start (zero on invalid UTF-8), rdx=length.
 * No reliance on NUL termination or locale. */
.global trim_utf8
.type trim_utf8,@function
trim_utf8:
 add rsi, rdi
 xor r10d, r10d
 mov r11, rdi
.Ltrim_next:
 cmp rdi, rsi
 jae .Ltrim_done
 mov r8, rdi
 movzx r9d, byte ptr [rdi]
 inc rdi
 cmp r9d, 0x80
 jb .Lwhite
 cmp r9d, 0xc2
 jb .Ltrim_bad
 cmp r9d, 0xe0
 jb .Ltwo
 cmp r9d, 0xf0
 jb .Lthree
 cmp r9d, 0xf5
 jae .Ltrim_bad
 mov ecx, 3
 and r9d, 7
 mov edx, 0x10000
 jmp .Lcont
.Lthree:
 mov ecx, 2
 and r9d, 15
 mov edx, 0x800
 jmp .Lcont
.Ltwo:
 mov ecx, 1
 and r9d, 31
 mov edx, 0x80
.Lcont:
 cmp rdi, rsi
 jae .Ltrim_bad
 movzx eax, byte ptr [rdi]
 inc rdi
 sub eax, 0x80
 cmp eax, 63
 ja .Ltrim_bad
 shl r9d, 6
 or r9d, eax
 dec ecx
 jnz .Lcont
 cmp r9d, edx
 jb .Ltrim_bad
 cmp r9d, 0x10ffff
 ja .Ltrim_bad
 lea eax, [r9-0xd800]
 cmp eax, 0x7ff
 jbe .Ltrim_bad
.Lwhite:
 cmp r9d, 32
 je .Ltrim_next
 lea eax, [r9-9]
 cmp eax, 4
 jbe .Ltrim_next
 cmp r9d, 0x85
 je .Ltrim_next
 cmp r9d, 0xa0
 je .Ltrim_next
 cmp r9d, 0x1680
 je .Ltrim_next
 lea eax, [r9-0x2000]
 cmp eax, 10
 jbe .Ltrim_next
 lea eax, [r9-0x2028]
 cmp eax, 1
 jbe .Ltrim_next
 cmp r9d, 0x202f
 je .Ltrim_next
 cmp r9d, 0x205f
 je .Ltrim_next
 cmp r9d, 0x3000
 je .Ltrim_next
 test r10, r10
 cmovz r10, r8
 mov r11, rdi
 jmp .Ltrim_next
.Ltrim_done:
 test r10, r10
 cmovz r10, rdi
 mov rax, r10
 mov rdx, r11
 sub rdx, r10
 /* all-white input: zero length, not a negative span */
 test rdx, rdx
 jns .Ltrim_ret
 xor edx, edx
.Ltrim_ret:
 ret
.Ltrim_bad:
 xor eax, eax
 xor edx, edx
 ret

/* open/read-to-EOF/close; accepts exactly 256 bytes, rejects longer input.
 * EINTR retries, short reads, embedded NUL and UTF-8 checked by consumers.
 * Returns a trimmed view into shared attr, rax=0 on failure, rdx=len. */
.global read_attr
.type read_attr,@function
read_attr:
 ENTER
 mov r13, rdi
.Lopen_retry:
 mov rdi, r13
 xor esi, esi
 xor eax, eax
 call open@PLT
 test eax, eax
 jns .Lopen_ok
 call __errno_location@PLT
 cmp dword ptr [rax], 4
 je .Lopen_retry
 jmp .Lread_bad
.Lopen_ok:
 mov ebx, eax
 xor r12d, r12d
.Lread_loop:
 mov edi, ebx
 lea rsi, [rip+attr]
 add rsi, r12
 mov edx, 257
 sub rdx, r12
 call read@PLT
 test rax, rax
 js .Lread_error
 jz .Lread_eof
 add r12, rax
 cmp r12, 256
 jbe .Lread_loop
 jmp .Lread_close_bad
.Lread_error:
 call __errno_location@PLT
 cmp dword ptr [rax], 4
 je .Lread_loop
.Lread_close_bad:
 mov edi, ebx
 call close@PLT
.Lread_bad:
 xor eax, eax
 xor edx, edx
 LEAVE
.Lread_eof:
 mov edi, ebx
 call close@PLT
 lea rdi, [rip+attr]
 mov byte ptr [rdi+r12], 0
 mov rsi, r12
 call trim_utf8
 test rax, rax
 jz .Lread_bad
 /* All callers needing strings receive a terminator after the trimmed view. */
 mov byte ptr [rax+rdx], 0
 LEAVE

/* Strict unsigned decimal parser, optional +, checked u64 arithmetic. */
.global parse_u64
.type parse_u64,@function
parse_u64:
 xor eax, eax
 test rsi, rsi
 jz .Lparse_bad
 cmp byte ptr [rdi], '+'
 jne .Lparse_digits
 inc rdi
 dec rsi
 jz .Lparse_bad
.Lparse_digits:
 mov r8d, 10
.Lparse_loop:
 movzx ecx, byte ptr [rdi]
 sub ecx, '0'
 cmp ecx, 9
 ja .Lparse_bad
 mul r8
 test rdx, rdx
 jnz .Lparse_bad
 add rax, rcx
 jc .Lparse_bad
 inc rdi
 dec rsi
 jnz .Lparse_loop
 mov edx, 1
 ret
.Lparse_bad:
 xor edx, edx
 ret
.global parse_i32
.type parse_i32,@function
parse_i32:
 ENTER
 xor ebx, ebx
 test rsi, rsi
 jz .Li32_bad
 cmp byte ptr [rdi], '-'
 jne .Li32_parse
 inc rdi
 dec rsi
 mov ebx, 1
 /* A second sign is not legal. */
 test rsi, rsi
 jz .Li32_bad
 cmp byte ptr [rdi], '+'
 je .Li32_bad
.Li32_parse:
 call parse_u64
 test edx, edx
 jz .Li32_bad
 mov ecx, 2147483647
 add rcx, rbx
 cmp rax, rcx
 ja .Li32_bad
 test ebx, ebx
 jz .Li32_ok
 neg eax
.Li32_ok:
 mov edx, 1
 LEAVE
.Li32_bad:
 xor edx, edx
 LEAVE
.global read_degree
.type read_degree,@function
read_degree:
 ENTER
 call read_attr
 test rax, rax
 jz .Ldegree_bad
 mov rdi, rax
 mov rsi, rdx
 call parse_i32
 test edx, edx
 jz .Ldegree_bad
 /* Preserve existing release-Rust wrapping addition and truncation to zero. */
 add eax, 500
 cdq
 mov ecx, 1000
 idiv ecx
 mov edx, 1
 LEAVE
.Ldegree_bad:
 xor edx, edx
 LEAVE

/* rdi=dest eax=value edx=valid -> rax=next dest. */
.global append_field
.type append_field,@function
append_field:
 test edx, edx
 jz .Lmissing
 test eax, eax
 jns .Lpositive
 mov byte ptr [rdi], '-'
 inc rdi
 neg eax
.Lpositive:
 sub rsp, 24
 lea r8, [rsp+24]
 mov ecx, 10
.Lformat_loop:
 xor edx, edx
 div ecx
 add dl, '0'
 dec r8
 mov byte ptr [r8], dl
 test eax, eax
 jnz .Lformat_loop
 lea r9, [rsp+24]
.Lformat_copy:
 mov dl, byte ptr [r8]
 mov byte ptr [rdi], dl
 inc rdi
 inc r8
 cmp r8, r9
 jb .Lformat_copy
 add rsp, 24
 mov rax, rdi
 ret
.Lmissing:
 mov byte ptr [rdi], '-'
 lea rax, [rdi+1]
 ret

/* Find matching label in a hwmon directory. Returns strdup'd input or NULL.
 * glob_t Linux/glibc ABI: count@0, pathv@8, total size 72. */
.type labeled_input,@function
labeled_input:
 ENTER 4224
 mov rbx, rsi
 lea r12, [rbp-4144]
 mov rcx, rdi
 mov rdi, r12
 mov esi, 4096
 lea rdx, [rip+label_fmt]
 xor eax, eax
 call snprintf@PLT
 cmp eax, 4096
 jae .Llabel_none
 lea r13, [rbp-4224]
 mov rdi, r13
 xor esi, esi
 mov edx, 72
 call memset@PLT
 mov rdi, r12
 xor esi, esi
 xor edx, edx
 mov rcx, r13
 call glob@PLT
 test eax, eax
 jnz .Llabel_none_free
 xor r14d, r14d
.Llabel_loop:
 cmp r14, qword ptr [r13]
 jae .Llabel_none_free
 mov rax, [r13+8]
 mov r15, [rax+r14*8]
 mov rdi, r15
 call read_attr
 test rax, rax
 jz .Llabel_next
 /* Compare lengths too: embedded NUL must never match a label. */
 mov [rbp-4232], rdx
 mov [rbp-4240], rax
 mov rdi, rbx
 call strlen@PLT
 cmp rax, [rbp-4232]
 jne .Llabel_next
 mov rdi, [rbp-4240]
 mov rsi, rbx
 call strcmp@PLT
 test eax, eax
 jnz .Llabel_next
 mov rdi, r15
 call strlen@PLT
 cmp rax, 6
 jb .Llabel_next
 sub eax, 6
 mov ecx, eax
 mov r8, r15
 mov rdi, r12
 mov esi, 4096
 lea rdx, [rip+input_fmt]
 xor eax, eax
 call snprintf@PLT
 cmp eax, 4096
 jae .Llabel_next
 mov rdi, r12
 xor esi, esi
 call access@PLT
 test eax, eax
 jnz .Llabel_next
 mov rdi, r12
 call strdup@PLT
 mov rbx, rax
 jmp .Llabel_free
.Llabel_next:
 inc r14
 jmp .Llabel_loop
.Llabel_none_free:
 xor ebx, ebx
.Llabel_free:
 mov rdi, r13
 call globfree@PLT
 mov rax, rbx
 LEAVE 4224
.Llabel_none:
 xor eax, eax
 LEAVE 4224

/* Disk record: input pointer, u32 index (+padding), model pointer, ordinal. */
.type disk_compare,@function
disk_compare:
 mov eax, [rdi+8]
 cmp eax, [rsi+8]
 mov eax, 1
 ja .Lcompare_ret
 mov eax, -1
 jb .Lcompare_ret
 mov rax, [rdi+24]
 cmp rax, [rsi+24]
 mov eax, 1
 ja .Lcompare_ret
 mov eax, -1
 jb .Lcompare_ret
 xor eax, eax
.Lcompare_ret:
 ret

.global discover
.type discover,@function
discover:
 ENTER 4304
 lea r12, [rbp-4144]
 lea r13, [rbp-4224]
 mov rdi, r13
 xor esi, esi
 mov edx, 72
 call memset@PLT
 lea rdi, [rip+hw_pattern]
 xor esi, esi
 xor edx, edx
 mov rcx, r13
 call glob@PLT
 test eax, eax
 jnz .Ldiscover_hw_done
 xor r14d, r14d
.Lhw_loop:
 cmp r14, qword ptr [r13]
 jae .Ldiscover_hw_done
 mov rax, [r13+8]
 mov r15, [rax+r14*8]
 mov rdi, r12
 mov esi, 4096
 lea rdx, [rip+name_fmt]
 mov rcx, r15
 xor eax, eax
 call snprintf@PLT
 cmp eax, 4096
 jae .Lhw_next
 mov rdi, r12
 call read_attr
 test rax, rax
 jz .Lhw_next
 mov rbx, rax
 cmp rdx, 7
 jne .Lcheck_nvme
 cmp qword ptr [rip+cpu_path], 0
 jne .Lhw_next
 mov rdi, rbx
 lea rsi, [rip+cpu_name]
 call strcmp@PLT
 test eax, eax
 jnz .Lhw_next
 mov rdi, r15
 lea rsi, [rip+cpu_label]
 call labeled_input
 mov [rip+cpu_path], rax
 jmp .Lhw_next
.Lcheck_nvme:
 cmp rdx, 4
 jne .Lhw_next
 mov rdi, rbx
 lea rsi, [rip+disk_name]
 call strcmp@PLT
 test eax, eax
 jnz .Lhw_next
 mov rdi, r15
 lea rsi, [rip+disk_label]
 call labeled_input
 test rax, rax
 jz .Lhw_next
 mov [rbp-4240], rax
 mov rdi, r12
 mov esi, 4096
 lea rdx, [rip+device_fmt]
 mov rcx, r15
 xor eax, eax
 call snprintf@PLT
 mov rdi, r12
 xor esi, esi
 call realpath@PLT
 mov ebx, -1
 test rax, rax
 jz .Ldisk_index_done
 mov [rbp-4248], rax
 mov rdi, rax
 mov esi, '/'
 call strrchr@PLT
 test rax, rax
 jz .Ldisk_index_free
 lea rdi, [rax+1]
 cmp dword ptr [rdi], 0x656d766e
 jne .Ldisk_index_free
 add rdi, 4
 mov [rbp-4256], rdi
 call strlen@PLT
 mov rsi, rax
 mov rdi, [rbp-4256]
 call parse_u64
 test edx, edx
 jz .Ldisk_index_free
 mov ecx, 0xffffffff
 cmp rax, rcx
 ja .Ldisk_index_free
 mov ebx, eax
.Ldisk_index_free:
 mov rdi, [rbp-4248]
 call free@PLT
.Ldisk_index_done:
 mov [rbp-4264], ebx
 lea rax, [rip+unknown]
 mov [rbp-4272], rax
 cmp ebx, -1
 je .Ldisk_model_done
 mov rdi, r12
 mov esi, 4096
 lea rdx, [rip+model_fmt]
 mov ecx, ebx
 xor eax, eax
 call snprintf@PLT
 mov rdi, r12
 call read_attr
 test rax, rax
 jz .Ldisk_model_done
 mov rdi, rax
 call strdup@PLT
 test rax, rax
 jz .Loom
 mov [rbp-4272], rax
.Ldisk_model_done:
 mov rbx, [rip+disk_count]
 lea rsi, [rbx+1]
 imul rsi, 32
 mov rdi, [rip+disks]
 call realloc@PLT
 test rax, rax
 jz .Loom
 mov [rip+disks], rax
 imul rbx, 32
 add rbx, rax
 mov rax, [rbp-4240]
 mov [rbx], rax
 mov eax, [rbp-4264]
 mov [rbx+8], eax
 mov rax, [rbp-4272]
 mov [rbx+16], rax
 mov rax, [rip+disk_count]
 mov [rbx+24], rax
 inc qword ptr [rip+disk_count]
.Lhw_next:
 inc r14
 jmp .Lhw_loop
.Ldiscover_hw_done:
 mov rdi, r13
 call globfree@PLT
 mov rdi, [rip+disks]
 mov rsi, [rip+disk_count]
 mov edx, 32
 lea rcx, [rip+disk_compare]
 call qsort@PLT
 /* GPU: load only; NVML initialization is deferred until after suspend gate. */
 lea rdi, [rip+lib1]
 mov esi, 2
 call dlopen@PLT
 test rax, rax
 jnz .Llib_found
 lea rdi, [rip+lib2]
 mov esi, 2
 call dlopen@PLT
 test rax, rax
 jnz .Llib_found
 lea rdi, [rip+lib3]
 mov esi, 2
 call dlopen@PLT
.Llib_found:
 mov [rip+lib_handle], rax
 mov rdi, r13
 xor esi, esi
 mov edx, 72
 call memset@PLT
 lea rdi, [rip+pci_pattern]
 xor esi, esi
 xor edx, edx
 mov rcx, r13
 call glob@PLT
 test eax, eax
 jnz .Lpci_done
 xor r14d, r14d
.Lpci_loop:
 cmp r14, [r13]
 jae .Lpci_done
 mov rax, [r13+8]
 mov r15, [rax+r14*8]
 mov rdi, r12
 mov esi, 4096
 lea rdx, [rip+vendor_fmt]
 mov rcx, r15
 xor eax, eax
 call snprintf@PLT
 cmp eax, 4096
 jae .Lpci_next
 mov rdi, r12
 call read_attr
 test rax, rax
 jz .Lpci_next
 cmp rdx, 6
 jne .Lpci_next
 cmp dword ptr [rax], 0x30317830
 jne .Lpci_next
 cmp word ptr [rax+4], 0x6564
 jne .Lpci_next
 mov rdi, r12
 mov esi, 4096
 lea rdx, [rip+class_fmt]
 mov rcx, r15
 xor eax, eax
 call snprintf@PLT
 cmp eax, 4096
 jae .Lpci_next
 mov rdi, r12
 call read_attr
 test rax, rax
 jz .Lpci_next
 cmp rdx, 4
 jb .Lpci_next
 cmp dword ptr [rax], 0x33307830
 jne .Lpci_next
 mov rdi, r12
 mov esi, 4096
 lea rdx, [rip+status_fmt]
 mov rcx, r15
 xor eax, eax
 call snprintf@PLT
 cmp eax, 4096
 jae .Lpci_next
 mov rdi, r12
 xor esi, esi
 call access@PLT
 test eax, eax
 jnz .Lpci_next
 mov rdi, r12
 call strdup@PLT
 test rax, rax
 jz .Loom
 mov [rip+runtime_path], rax
 jmp .Lpci_done
.Lpci_next:
 inc r14
 jmp .Lpci_loop
.Lpci_done:
 mov rdi, r13
 call globfree@PLT
 /* 12 bytes per signed field + separator; two mandatory fields + newline. */
 mov rax, [rip+disk_count]
 add rax, 2
 imul rax, 12
 inc rax
 mov [rip+output_size], rax
 mov rdi, rax
 call malloc@PLT
 test rax, rax
 jz .Loom
 mov [rip+output], rax
 LEAVE 4304
.Loom:
 mov edi, 1
 call exit@PLT

.type read_gpu,@function
read_gpu:
 ENTER 16
 cmp qword ptr [rip+lib_handle], 0
 je .Lgpu_bad
 cmp dword ptr [rip+gpu_always], 0
 jne .Lgpu_init
 mov rdi, [rip+runtime_path]
 test rdi, rdi
 jz .Lgpu_init
 call read_attr
 test rax, rax
 jz .Lgpu_init
 cmp rdx, 9
 jne .Lgpu_init
 mov rdi, rax
 lea rsi, [rip+suspended]
 call strcmp@PLT
 test eax, eax
 jz .Lgpu_bad
.Lgpu_init:
 cmp dword ptr [rip+session_ready], 0
 jne .Lgpu_query
 mov rdi, [rip+lib_handle]
 lea rsi, [rip+sym_init]
 call dlsym@PLT
 test rax, rax
 jz .Lgpu_bad
 mov [rip+init_fn], rax
 mov rdi, [rip+lib_handle]
 lea rsi, [rip+sym_handle]
 call dlsym@PLT
 test rax, rax
 jz .Lgpu_bad
 mov [rip+handle_fn], rax
 mov rdi, [rip+lib_handle]
 lea rsi, [rip+sym_temp]
 call dlsym@PLT
 test rax, rax
 jz .Lgpu_bad
 mov [rip+temp_fn], rax
 call qword ptr [rip+init_fn]
 test eax, eax
 jnz .Lgpu_bad
 xor edi, edi
 lea rsi, [rip+gpu_device]
 mov qword ptr [rsi], 0
 call qword ptr [rip+handle_fn]
 test eax, eax
 jnz .Lgpu_bad
 mov dword ptr [rip+session_ready], 1
.Lgpu_query:
 mov dword ptr [rbp-48], 0
 mov rdi, [rip+gpu_device]
 xor esi, esi
 lea rdx, [rbp-48]
 call qword ptr [rip+temp_fn]
 test eax, eax
 jnz .Lgpu_bad
 mov eax, [rbp-48]
 mov edx, 1
 LEAVE 16
.Lgpu_bad:
 xor edx, edx
 LEAVE 16

/* One sample, no per-sample allocation. rax=buffer, rdx=length incl newline. */
.global sample
.type sample,@function
sample:
 ENTER
 mov rbx, [rip+output]
 mov rdi, [rip+cpu_path]
 xor edx, edx
 test rdi, rdi
 jz .Lsample_cpu
 call read_degree
.Lsample_cpu:
 mov rdi, rbx
 call append_field
 mov rbx, rax
 mov byte ptr [rbx], ' '
 inc rbx
 call read_gpu
 mov rdi, rbx
 call append_field
 mov rbx, rax
 xor r12d, r12d
 mov r13, [rip+disks]
.Lsample_disks:
 cmp r12, [rip+disk_count]
 jae .Lsample_done
 mov byte ptr [rbx], ' '
 inc rbx
 mov rdi, [r13]
 call read_degree
 mov rdi, rbx
 call append_field
 mov rbx, rax
 add r13, 32
 inc r12
 jmp .Lsample_disks
.Lsample_done:
 mov byte ptr [rbx], 10
 inc rbx
 mov rax, [rip+output]
 mov rdx, rbx
 sub rdx, rax
 LEAVE

.global write_sample
.type write_sample,@function
write_sample:
 ENTER
 call sample
 mov rbx, rax
 mov r12, rdx
.Lwrite_loop:
 mov edi, 1
 mov rsi, rbx
 mov rdx, r12
 call write@PLT
 test rax, rax
 js .Lwrite_error
 jz .Lwrite_bad
 add rbx, rax
 sub r12, rax
 jnz .Lwrite_loop
 xor eax, eax
 LEAVE
.Lwrite_error:
 call __errno_location@PLT
 cmp dword ptr [rax], 4
 je .Lwrite_loop
.Lwrite_bad:
 mov eax, 1
 LEAVE

.type log_summary,@function
log_summary:
 ENTER 32
 lea rdx, [rip+cpu_no]
 cmp qword ptr [rip+cpu_path], 0
 je .Llog_gpu
 lea rdx, [rip+cpu_yes]
.Llog_gpu:
 lea rcx, [rip+gpu_no]
 cmp qword ptr [rip+lib_handle], 0
 je .Llog_header
 lea rcx, [rip+gpu_yes]
 cmp qword ptr [rip+runtime_path], 0
 je .Llog_header
 lea rcx, [rip+gpu_gate]
.Llog_header:
 mov rdi, [rip+stderr]
 lea rsi, [rip+summary_fmt]
 mov r8, [rip+disk_count]
 xor eax, eax
 call fprintf@PLT
 xor ebx, ebx
 mov r12, [rip+disks]
.Llog_loop:
 cmp rbx, [rip+disk_count]
 jae .Llog_done
 lea rcx, [rip+node_unknown]
 cmp dword ptr [r12+8], -1
 je .Llog_disk
 lea rdi, [rbp-80]
 mov esi, 32
 lea rdx, [rip+node_fmt]
 mov ecx, [r12+8]
 xor eax, eax
 call snprintf@PLT
 lea rcx, [rbp-80]
.Llog_disk:
 mov rdi, [rip+stderr]
 lea rsi, [rip+summary_disk]
 mov rdx, rbx
 mov r8, [r12+16]
 xor eax, eax
 call fprintf@PLT
 inc rbx
 add r12, 32
 jmp .Llog_loop
.Llog_done:
 LEAVE 32

#ifndef TEMPORION_X86_NO_MAIN
.global main
.type main,@function
main:
 ENTER 32
 /* Rust ignores SIGPIPE; match its clean reader-disconnect exit. */
 mov edi, 13
 mov esi, 1
 call signal@PLT
 mov r12d, 2000
 lea rdi, [rip+env_interval]
 call getenv@PLT
 test rax, rax
 jz .Linterval_ready
 mov rbx, rax
 mov rdi, rax
 call strlen@PLT
 mov rdi, rbx
 mov rsi, rax
 call trim_utf8
 test rax, rax
 jz .Linterval_ready
 mov rdi, rax
 mov rsi, rdx
 call parse_u64
 test edx, edx
 jz .Linterval_ready
 mov r12, rax
.Linterval_ready:
 mov eax, 100
 cmp r12, rax
 cmovb r12, rax
 mov rax, r12
 xor edx, edx
 mov ecx, 1000
 div rcx
 mov [rip+interval], rax
 imul rdx, 1000000
 mov [rip+interval+8], rdx
 lea rdi, [rip+env_always]
 call getenv@PLT
 test rax, rax
 jz .Lmain_discover
 cmp byte ptr [rax], '1'
 jne .Lmain_discover
 cmp byte ptr [rax+1], 0
 jne .Lmain_discover
 mov dword ptr [rip+gpu_always], 1
.Lmain_discover:
 call discover
 call log_summary
.Lmain_loop:
 call write_sample
 test eax, eax
 jnz .Lmain_done
 lea rdi, [rip+interval]
 lea rsi, [rbp-64]
.Lsleep:
 call nanosleep@PLT
 test eax, eax
 jz .Lmain_loop
 call __errno_location@PLT
 cmp dword ptr [rax], 4
 jne .Lmain_done
 lea rdi, [rbp-64]
 mov rsi, rdi
 jmp .Lsleep
.Lmain_done:
 xor eax, eax
 LEAVE 32
#endif
.section .note.GNU-stack,"",@progbits
