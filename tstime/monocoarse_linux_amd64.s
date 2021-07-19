// Copyright (c) 2021 Tailscale Inc & AUTHORS All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Adapted from code in the Go runtime package at Go 1.16.6:

// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// +build go1.16
// +build !go1.17

#include "go_asm.h"
#include "textflag.h"

#define	get_tls(r)	MOVQ TLS, r
#define	g(r)	0(r)(TLS*1)

#define SYS_clock_gettime	228

// Hard-coded offsets into runtime structs.
// Generated by adding the following code
// to package runtime and then executing
// and empty func main:
//
// func init() {
// 	println("#define g_m", unsafe.Offsetof(g{}.m))
// 	println("#define g_sched", unsafe.Offsetof(g{}.sched))
// 	println("#define gobuf_sp", unsafe.Offsetof(g{}.sched.sp))
// 	println("#define m_g0", unsafe.Offsetof(m{}.g0))
// 	println("#define m_curg", unsafe.Offsetof(m{}.curg))
// 	println("#define m_vdsoSP", unsafe.Offsetof(m{}.vdsoSP))
// 	println("#define m_vdsoPC", unsafe.Offsetof(m{}.vdsoPC))
// }

#define g_m 48
#define g_sched 56
#define gobuf_sp 0
#define m_g0 0
#define m_curg 192
#define m_vdsoSP 832
#define m_vdsoPC 840

// func monoClock(clock int) int64
TEXT ·monoClock(SB),NOSPLIT,$16-16
	MOVQ	clock+0(FP), DI

	// Switch to g0 stack.

	MOVQ	SP, R12	// Save old SP; R12 unchanged by C code.

	get_tls(CX)
	MOVQ	g(CX), AX
	MOVQ	g_m(AX), BX // BX unchanged by C code.

	// Set vdsoPC and vdsoSP for SIGPROF traceback.
	// Save the old values on stack and restore them on exit,
	// so this function is reentrant.
	MOVQ	m_vdsoPC(BX), CX
	MOVQ	m_vdsoSP(BX), DX
	MOVQ	CX, 0(SP)
	MOVQ	DX, 8(SP)

	LEAQ	ret+8(FP), DX
	MOVQ	-8(DX), CX
	MOVQ	CX, m_vdsoPC(BX)
	MOVQ	DX, m_vdsoSP(BX)

	CMPQ	AX, m_curg(BX)	// Only switch if on curg.
	JNE	noswitch

	MOVQ	m_g0(BX), DX
	MOVQ	(g_sched+gobuf_sp)(DX), SP	// Set SP to g0 stack

noswitch:
	SUBQ	$16, SP		// Space for results
	ANDQ	$~15, SP	// Align for C code

	LEAQ	0(SP), SI
	MOVQ	runtime·vdsoClockgettimeSym(SB), AX
	CMPQ	AX, $0
	JEQ	fallback
	CALL	AX
ret:
	MOVQ	0(SP), AX	// sec
	MOVQ	8(SP), DX	// nsec
	MOVQ	R12, SP		// Restore real SP
	// Restore vdsoPC, vdsoSP
	// We don't worry about being signaled between the two stores.
	// If we are not in a signal handler, we'll restore vdsoSP to 0,
	// and no one will care about vdsoPC. If we are in a signal handler,
	// we cannot receive another signal.
	MOVQ	8(SP), CX
	MOVQ	CX, m_vdsoSP(BX)
	MOVQ	0(SP), CX
	MOVQ	CX, m_vdsoPC(BX)
	// sec is in AX, nsec in DX
	// return nsec in AX
	IMULQ	$1000000000, AX
	ADDQ	DX, AX
	MOVQ	AX, ret+8(FP)
	RET
fallback:
	MOVQ	$SYS_clock_gettime, AX
	SYSCALL
	JMP	ret
