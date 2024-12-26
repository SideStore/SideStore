//
//  ptrace.h
//  AltStore
//
//  Created by June P on 12/26/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

#ifndef ptrace_h
#define ptrace_h

int ptrace(int request, pid_t pid, caddr_t addr, int data);

#endif /* ptrace_h */
