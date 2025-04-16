//
//  ptrace.m
//  AltStore
//
//  Created by June P on 12/26/24.
//  Copyright © 2024 SideStore. All rights reserved.
//


int ptrace(int request, pid_t pid, caddr_t addr, int data) {
    int result = 0;
    __asm__ (
        "MOV x16, #26          \n"   // Syscall number for ptrace
        "MOV x0, %[request]    \n"   // Pass request to x0
        "MOV x1, %[pid]        \n"   // Pass pid to x1
        "MOV x2, %[addr]       \n"   // Pass addr to x2
        "MOV x3, %[data]       \n"   // Pass data to x3
        "SVC 0                 \n"   // Make the syscall (0 for ARM64)
        : [result] "=r" (result)     // No output
        : [request] "r" (request),   // Input constraints
          [pid] "r" (pid),
          [addr] "r" (addr),
          [data] "r" (data)
        : "x0", "x1", "x2", "x3", "x16"  // Clobber list
    );
    return result;
}
