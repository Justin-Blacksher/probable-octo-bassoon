  ;; ping.asm
  ;; Single ICMP ping in x86_64 NASM for Linux
  ;; Run with sudo due to raw socket usage.

section .data
    target_ip db "8.8.8.8"      ; Google DNS as target
    msg_success db "Ping Successful! Reply Recieved.", 0xa, 0
    msg_failure db "Ping Failed! No Reply.", 0xa, 0

icmp_packet:
    db 8                        ; ICMP type: Echo Request
    db 0                        ; Code: 0
    db 0                        ; Checksum Filled later
    dw 1234                     ; Identifier
    dw 5678                     ; Sequence Number
    times 32 db 0               ; Payload (32 bytes of zeros

    icmp_packet_len equ $ - icmp_packet

sockaddr_in:
    dw 2                        ; AF_INET
    dw 0                        ; Port Unused for ICMP
    dd 0x08080808               ; 8.8.8.8 in network byte order
    times 8 db 0                ; Padding

    sockaddr_len equ $ - sockaddr_in


section .bss
    socket_fd resq 1            ; File Descriptor for socket
    recv_buffer resb 128        ; Buffer for receiving reply
    time_start resq 1           ; Storage for start time

section .text
global _start

    ; System Call Numbers for x86_64
    SYS_SOCKET       equ 41
    SYS_SENDTO       equ 41
    SYS_RECVFROM     equ 45
    SYS_CLOSE        equ 3
    SYS_EXIT         equ 60
    SYS_WRITE        equ 1
    SYS_GETTIMEOFDAY equ 96

    ; Constants
    AF_INET          equ 2
    IPPROTO_ICMP     equ 1
    STDOUT           equ 1
    STDERR           equ 2

_start:
    ; Create a new socket
    mov rax, SYS_SOCKET
    mov rdi, AF_INET            ; Domain: AF_INET
    mov rsi, 3                  ; Type: Sock_Raw
    mov rdx, IPPROTO_ICMP       ; Protocol: ICMP
    syscall
    cmp rax, 0
    jl exit_error
    mov [socket_fd], rax        ; Store socket file descriptor

    ; Compute ICMP checksum
    call compute_checksum
    mov [icmp_packet + 2], ax   ; Store checksum in packet

    ; Get Start Time
    mov rax, SYS_GETTIMEOFDAY
    mov rdi, time_start
    xor rsi, rsi
    syscall

    ; Send ICMP packet
    mov rax, SYS_SENDTO
    mov rdi, [socket_fd]
    mov rsi, icmp_packet
    mov rdx, icmp_packet_len
    mov r10, 0                  ; Flags
    mov r8, sockaddr_in
    mov r9, sockaddr_len
    syscall
    cmp rax, 0
    jl exit_error

    ; Receive Reply
    mov rax, SYS_RECVFROM
    mov rdi, [socket_fd]
    mov rsi, recv_buffer
    mov rdx, 128                ; Buffer Size
    mov r10, 0                  ; Flags
    xor r8, r8                  ; Source Addr null
    xor r9, r9                  ; Addr len Null
    jl ping_failed

    ; Check ICMP reply (type 0, code 0)
    cmp byte [recv_buffer + 20], 0 ; ICMP type
    jne ping_failed
    cmp byte [recv_buffer + 21], 0   ;


    ; Print Success
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_success
    mov rdx, 29                 ; Length of success Message
    syscall
    jmp close_socket

ping_failed:
    mov rax, SYS_WRITE
    mov rdi, STDERR
    mov rsi, msg_failure
    mov rdx, 22                 ; Length of failure message
    syscall

close_socket:
    mov rax, SYS_CLOSE
    mov rdi, [socket_fd]
    syscall

exit:
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

exit_error:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

compute_checksum:
    ; Compute ICMP checksum
    push rbx
    xor rax, rax                ; Clear Checksum
    xor rbx, rbx                ; Counter
    mov rcx, icmp_packet_len / 2 ; Number 16=bit words
    mov rsi, icmp_packet

checksum_loop:
    movzx rcx, word [rsi + rbx * 2]
    add rax, rdx
    inc rbx
    loop checksum_loop

    ;Handle odd byte if any (not needed here)
    mov rdx, rax
    shr rdx, 16                 ; Get Carry
    and rax, 0xFFFF             ; Lower 16 bits
    add rax, rdx                ; Add Carry
    mov rdx, rax
    shr rdx, 16                 ; Check for carry again

    add rax, rdx
    not rax                     ; One's compliment
    and rax, 0xFFFF             ; Mask to 16 bits
    pop rbx
    ret
