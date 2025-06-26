; ping.asm
; Single ICMP ping in x86_64 NASM for Linux
; Run with sudo due to raw socket usage.

section .data
    target_ip db "8.8.8.8", 0             ; For reference, not used
    msg_success db "Ping Successful! Reply Recieved.", 0xa
    len_success equ $-msg_success
    msg_failure db "Ping Failed! No Reply.", 0xa
    len_failure equ $-msg_failure

icmp_packet:
    db 8                                  ; ICMP type: Echo Request
    db 0                                  ; Code: 0
    dw 0                                  ; Checksum (filled in later)
    dw 1234                               ; Identifier
    dw 5678                               ; Sequence Number
    times 32 db 0                         ; Payload (32 bytes of zeros)
icmp_packet_len equ $-icmp_packet

sockaddr_in:
    dw 2                                  ; AF_INET
    dw 0                                  ; Port (unused)
    dd 0x08080808                         ; 8.8.8.8, network byte order
    times 8 db 0                          ; Padding
sockaddr_len equ $-sockaddr_in

section .bss
    socket_fd    resq 1                   ; File Descriptor for socket
    recv_buffer  resb 128                 ; Buffer for receiving reply
    time_start   resq 1                   ; Storage for start time

section .text
global _start

; Syscall numbers
SYS_SOCKET       equ 41
SYS_SENDTO       equ 44
SYS_RECVFROM     equ 45
SYS_CLOSE        equ 3
SYS_EXIT         equ 60
SYS_WRITE        equ 1
SYS_GETTIMEOFDAY equ 96

AF_INET          equ 2
IPPROTO_ICMP     equ 1
STDOUT           equ 1
STDERR           equ 2

_start:
    ; Create socket
    mov     rax, SYS_SOCKET
    mov     rdi, AF_INET
    mov     rsi, 3                      ; SOCK_RAW
    mov     rdx, IPPROTO_ICMP
    syscall
    cmp     rax, 0
    jl      exit_error
    mov     [socket_fd], rax

    ; Calculate ICMP checksum
    call    compute_checksum
    mov     word [icmp_packet+2], ax

    ; Get start time (optional, not used)
    mov     rax, SYS_GETTIMEOFDAY
    mov     rdi, time_start
    xor     rsi, rsi
    syscall

    ; Send ICMP packet
    mov     rax, SYS_SENDTO
    mov     rdi, [socket_fd]
    mov     rsi, icmp_packet
    mov     rdx, icmp_packet_len
    mov     r10, 0
    mov     r8, sockaddr_in
    mov     r9, sockaddr_len
    syscall
    cmp     rax, 0
    jl      exit_error

    ; Receive reply
    mov     rax, SYS_RECVFROM
    mov     rdi, [socket_fd]
    mov     rsi, recv_buffer
    mov     rdx, 128
    mov     r10, 0
    xor     r8, r8
    xor     r9, r9
    syscall
    cmp     rax, 0
    jl      ping_failed

    ; Check ICMP type/code in reply
    cmp     byte [recv_buffer+20], 0    ; Type == 0?
    jne     ping_failed
    cmp     byte [recv_buffer+21], 0    ; Code == 0?
    jne     ping_failed

    ; Print success
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT
    mov     rsi, msg_success
    mov     rdx, len_success
    syscall
    jmp     close_socket

ping_failed:
    mov     rax, SYS_WRITE
    mov     rdi, STDERR
    mov     rsi, msg_failure
    mov     rdx, len_failure
    syscall

close_socket:
    mov     rax, SYS_CLOSE
    mov     rdi, [socket_fd]
    syscall

exit:
    mov     rax, SYS_EXIT
    xor     rdi, rdi
    syscall

exit_error:
    mov     rax, SYS_EXIT
    mov     rdi, 1
    syscall

;----------------------------------------
; Compute ICMP packet checksum
; Returns result in AX
compute_checksum:
    push    rcx
    push    rdx
    push    rsi
    push    rbx
    xor     rax, rax
    xor     rbx, rbx
    mov     rcx, icmp_packet_len/2
    mov     rsi, icmp_packet
.cc_loop:
    mov     dx, [rsi+rbx*2]
    add     ax, dx
    inc     rbx
    loop    .cc_loop

    adc     ax, 0                    ; Add carry
    not     ax
    pop     rbx
    pop     rsi
    pop     rdx
    pop     rcx
    ret
