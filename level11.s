.intel_syntax noprefix
.global _start

.section .text
_start:     
    # socket + bind + listen
    mov rdi, 2
    mov rsi, 1
    mov rdx, 0
    mov rax, 41 
    syscall

    mov rdi, 3
    lea rsi, [rip+socket_addr]
    mov rdx, 16
    mov rax, 49
    syscall

    mov rdi, 3
    mov rsi, 0
    mov rax, 50
    syscall 

loop_accept:
    # 主循环：不断 accept 客户端连接
    mov rdi, 3
    mov rsi, 0
    mov rdx, 0
    mov rax, 43               # SYS_accept
    syscall                   # fd=4

    # fork 一次：子进程处理连接，父进程继续 accept
    mov rax, 57               # SYS_fork
    syscall
    mov r8, rax
	cmp r8, 0
	jne parent_process         # 非 0 为父进程
	cmp r8, 0
	je child_process          # 0 为子进程

child_process:
    # 子进程：只保留客户端 fd=4，关掉监听 fd=3
    mov rdi, 3
    mov rax, 3                # close(3)
    syscall

    # 读完整 HTTP 请求到 buffer
    mov rdi, 4
    lea rsi, buffer
    mov rdx, 512
    mov rax, 0                # read
    syscall
    mov r15, rax              # r15 = 读取长度

    # 判断是 POST 还是 GET：看第一个字节
    mov al, byte ptr [buffer]
    cmp al, 'P'
    je post_request
    cmp al, 'G'
    je get_request

get_request:
    # 解析 GET /path HTTP...
    lea rsi, buffer+4         # 跳过 "GET "
    lea rdi, file_path_get
loop_start_get:
    mov al, byte ptr [rsi]
    cmp al, ' '
    je get_file_path_get
    mov byte ptr [rdi], al
    inc rdi
    inc rsi
    jmp loop_start_get

get_file_path_get:
    # open(file_path_get, O_RDONLY)
    lea rdi, file_path_get
    mov rsi, 0
    mov rax, 2
    syscall                   # fd = 3

    # read(3, rsp, 256)
    mov rdi, 3
    mov rsi, rsp
    mov rdx, 256
    mov rax, 0
    syscall 
    mov r8, rax

    # close(3)
    mov rdi, 3
    mov rax, 3
    syscall

    # 写 HTTP 头
    mov rdi, 4
    lea rsi,[rip + ret_normal_msg] 
    mov rdx, 19
    mov rax, 1
    syscall

    # 写文件内容
    mov rdi, 4
    mov rsi, rsp
    mov rdx, r8
    mov rax, 1
    syscall

    # 结束子进程（这里没显式 close(4)，题目环境收尾）
    mov rdi,0
    mov rax,60
    syscall    

post_request:
    # POST 逻辑：保存 body 到文件
    mov r10, rax              # 这里 rax 已不用，随手存一下
    # 解析 POST /path...
    lea rsi, buffer+5         # 跳过 "POST "
    lea rdi, file_path
loop_start_post:
    mov al, byte ptr [rsi]
    cmp al, 0x20
    je get_file_path_post
    mov byte ptr [rdi], al
    inc rdi
    inc rsi
    jmp loop_start_post

get_file_path_post:
    # open(file_path, O_WRONLY|O_CREAT, 0777)
    lea rdi, file_path
    mov rsi, 01|0100
    mov rdx, 0x1FF
    mov rax, 2
    syscall                   # fd = 3

    # 下面逻辑与 level10 类似：跳过前 8 行，定位 body
    mov r12, 8                # 要跳过的 HTTP 头行数
    mov r8, 0                 # 当前已看到的换行数
    mov r9, 0                 # 当前偏移
    lea rsi, buffer
    lea rdi, content          # content 没实际用到

loop2_start_post:
    cmp r8, r12
    jge get_content           # 到第 8 行结束
    mov al, byte ptr [rsi]
    inc r9
    cmp al, '\n'
    je get_index 
    inc rsi
    jmp loop2_start_post

get_index:
    inc r8
    inc rsi
    jmp loop2_start_post

get_content:
    # r15 = 总读入长度，r9 = body 起始偏移
    sub r15, r9               # r15 = body 长度

    # write(3, buffer + r9, r15)
    mov rdi, 3
    lea rsi, buffer
    add rsi, r9
    mov rdx, r15
    mov rax, 1
    syscall
    
    # close(3)
    mov rdi, 3
    mov rax, 3
    syscall

    # 回一个 HTTP 200 头给客户端
    mov rdi, 4
    lea rsi,[rip + ret_normal_msg] 
    mov rdx, 19
    mov rax, 1
    syscall

    # 子进程结束
    mov rdi,0
    mov rax,60
    syscall

parent_process:
    # 父进程关闭本次连接 fd=4，然后回到 loop_accept 继续 accept 新连接
    mov rdi, 4
    mov rax, 3
    syscall
    jmp loop_accept

.section .data
socket_addr:
    .2byte 2
    .2byte 0x5000
    .4byte 0
    .8byte 0
ret_normal_msg:
    .ascii "HTTP/1.0 200 OK\r\n\r\n"
buffer:
    .space 512
file_path:
    .space 64 
file_path_get:
    .space 64
content:
    .space 256
reverse_content:
    .space 256               # 这里没用到，沿用之前模板
